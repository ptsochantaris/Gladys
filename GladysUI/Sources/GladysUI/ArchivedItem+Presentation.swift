import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

public extension ArchivedItem {
    private static let warmupLock = Semalot(tickets: UInt(ProcessInfo().processorCount + 1))
    private static let singleLock = Semalot(tickets: 1)

    func createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        if let presentationGenerator {
            return await presentationGenerator.value
        } else {
            let newTask = Task.detached { [weak self] in await self?._createPresentationInfo(style: style, expectedSize: expectedSize) }
            presentationGenerator = newTask
            defer { presentationGenerator = nil }
            return await newTask.value
        }
    }

    private func _createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        if Task.isCancelled {
            return nil
        }

        let lock = style == .widget ? ArchivedItem.singleLock : ArchivedItem.warmupLock
        await lock.takeTicket()
        defer {
            lock.returnTicket()
        }

        if Task.isCancelled {
            return nil
        }

        assert(!Thread.isMainThread)

        let topInfo = prepareTopText()
        let bottomInfo = prepareBottomText()
        var processedImage: CIImage?
        var originalSize: CGSize?
        if let img = await prepareImage(asThumbnail: style == .widget) {
            originalSize = img.size
            #if canImport(AppKit)
                if let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    processedImage = CIImage(cgImage: cgImage, options: [.nearestSampling: true])
                } else {
                    processedImage = nil
                }
            #else
                processedImage = CIImage(image: img, options: [.nearestSampling: true])
            #endif
        }

        if Task.isCancelled {
            return nil
        }

        var top = PresentationInfo.defaultCardColor
        var bottom = PresentationInfo.defaultCardColor

        if displayMode != .center, style == .square, let originalSize {
            if expectedSize.width > 0, topInfo.willBeVisible || bottomInfo.willBeVisible {
                let topDistancePercent = topInfo.heightEstimate(for: expectedSize.width) / expectedSize.height
                let bottomDistancePercent = bottomInfo.heightEstimate(for: expectedSize.width) / expectedSize.height

                let top = topInfo.willBeVisible ? topDistancePercent : nil
                let bottom = bottomInfo.willBeVisible ? bottomDistancePercent : nil
                if let withBlur = processedImage?.applyLensEffect(top: top, bottom: bottom) {
                    processedImage = withBlur.cropped(to: CGRect(origin: .zero, size: originalSize))
                }

                if Task.isCancelled {
                    return nil
                }
            }

            if topInfo.willBeVisible, let processedImage {
                top = processedImage.calculateOuterColor(size: originalSize, top: true) ?? PresentationInfo.defaultCardColor

                if Task.isCancelled {
                    return nil
                }
            }

            if bottomInfo.willBeVisible, let processedImage {
                bottom = processedImage.calculateOuterColor(size: originalSize, top: false) ?? PresentationInfo.defaultCardColor
            }
        }

        var result: IMAGE?
        if let processedImage, let originalSize {
            if let new = CIImage.sharedCiContext.createCGImage(processedImage, from: processedImage.extent) {
                #if canImport(AppKit)
                    result = IMAGE(cgImage: new, size: originalSize)
                #else
                    result = IMAGE(cgImage: new)
                #endif
            }
        }

        let p = PresentationInfo(
            id: uuid,
            topText: topInfo,
            top: top,
            bottomText: bottomInfo,
            bottom: bottom,
            image: result,
            highlightColor: shouldDisplayLoading ? .none : highlightColor,
            hasFullImage: displayMode.prefersFullSizeImage
        )

        presentationInfoCache[uuid] = p

        if Task.isCancelled {
            return nil
        }

        return p
    }

    private func prepareTopText() -> PresentationInfo.FieldContent {
        if !isLocked, let topString = displayText.0 {
            .text(topString)
        } else {
            .none
        }
    }

    private func prepareBottomText() -> PresentationInfo.FieldContent {
        if isLocked {
            if let lockHint {
                .hint(lockHint)
            } else {
                .none
            }
        } else if PersistedOptions.displayNotesInMainView, note.isPopulated {
            .note(note)
        } else if let url = associatedWebURL, backgroundInfoObject == nil {
            .link(url)
        } else {
            .none
        }
    }

    private func prepareImage(asThumbnail: Bool) async -> IMAGE? {
        assert(!Thread.isMainThread)

        if asThumbnail {
            return thumbnail
        }

        if let bgItem = backgroundInfoObject {
            if let mapItem = bgItem as? MKMapItem {
                let snapshotOptions = Images.SnapshotOptions(coordinate: mapItem.placemark.coordinate, range: 200, outputSize: imageDimensions)
                return try? await Images.shared.mapSnapshot(with: snapshotOptions)

            } else if let colour = bgItem as? COLOR {
                return IMAGE.block(color: colour, size: CGSize(width: 1, height: 1))
            }

            return nil
        }

        return displayIcon
    }
}
