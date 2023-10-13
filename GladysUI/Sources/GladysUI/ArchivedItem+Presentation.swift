import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

public extension ArchivedItem {
    private static let warmupLock = Semalot(tickets: UInt(ProcessInfo().processorCount + 1))
    private static let singleLock = Semalot(tickets: 1)

    func createPresentationInfo(style: ArchivedItemWrapper.Style, expectedWidth: CGFloat) async -> PresentationInfo? {
        if let presentationGenerator {
            return await presentationGenerator.value
        } else {
            let newTask = Task.detached { [weak self] in await self?._createPresentationInfo(style: style, expectedWidth: expectedWidth) }
            presentationGenerator = newTask
            defer { presentationGenerator = nil }
            return await newTask.value
        }
    }

    private func _createPresentationInfo(style: ArchivedItemWrapper.Style, expectedWidth: CGFloat) async -> PresentationInfo? {
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
        var result = await prepareImage(asThumbnail: style == .widget)

        if Task.isCancelled {
            return nil
        }

        var processedImage: CIImage?
        var top = PresentationInfo.defaultCardColor
        var bottom = PresentationInfo.defaultCardColor

        if displayMode != .center, style == .square, let prepared = result {
            if expectedWidth > 0, topInfo.willBeVisible || bottomInfo.willBeVisible {
                if processedImage == nil {
                    processedImage = prepared.createCiImage
                }

                let topDistance = topInfo.heightEstimate(for: expectedWidth, font: ItemView.titleFontLegacy)
                let bottomDistance = bottomInfo.heightEstimate(for: expectedWidth, font: ItemView.titleFontLegacy)

                let top = topInfo.willBeVisible ? topDistance : nil
                let bottom = bottomInfo.willBeVisible ? bottomDistance : nil
                if let previous = processedImage, let withBlur = previous.applyLensEffect(top: top, bottom: bottom) {
                    if let new = CIImage.sharedCiContext.createCGImage(withBlur, from: previous.extent) {
                        result = IMAGE(cgImage: new)
                    }
                    processedImage = withBlur
                }

                if Task.isCancelled {
                    return nil
                }
            }

            if topInfo.willBeVisible {
                if processedImage == nil {
                    processedImage = prepared.createCiImage
                }
                if let processedImage {
                    top = processedImage.calculateOuterColor(size: prepared.size, top: true) ?? PresentationInfo.defaultCardColor
                }

                if Task.isCancelled {
                    return nil
                }
            }

            if bottomInfo.willBeVisible {
                if processedImage == nil {
                    processedImage = prepared.createCiImage
                }
                if let processedImage {
                    bottom = processedImage.calculateOuterColor(size: prepared.size, top: false) ?? PresentationInfo.defaultCardColor
                }
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

        let result: IMAGE?
        if let bgItem = backgroundInfoObject {
            if let mapItem = bgItem as? MKMapItem {
                let snapshotOptions = Images.SnapshotOptions(coordinate: mapItem.placemark.coordinate, range: 200, outputSize: imageDimensions)
                #if canImport(AppKit)
                    result = try? await Images.shared.mapSnapshot(with: snapshotOptions)
                #else
                    result = try? await Images.shared.mapSnapshot(with: snapshotOptions).byPreparingForDisplay()
                #endif

            } else if let colour = bgItem as? COLOR {
                result = IMAGE.block(color: colour, size: CGSize(width: 1, height: 1))
            } else {
                result = nil
            }
        } else {
            #if canImport(AppKit)
                result = displayIcon
            #else
                result = displayIcon.preparingForDisplay()
            #endif
        }
        return result
    }
}
