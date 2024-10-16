import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

public extension ArchivedItem {
    private static let warmupLock = Semalot(tickets: UInt(ProcessInfo().processorCount))
    private static let singleLock = Semalot(tickets: 1)

    @discardableResult
    func createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        if let existing = presentationInfoCache[uuid] {
            log(">>> Using cached presentation info for \(uuid.uuidString)")
            return existing
        }

        if let info = await activePresentationGenerationResult {
            log(">>> Deduped presentation task \(uuid.uuidString)")
            return info
        }

        let newTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?._createPresentationInfo(style: style, expectedSize: expectedSize)
        }
        return await usingPresentationGenerator(newTask)
    }

    private nonisolated func _createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        assert(!Thread.isMainThread)

        let lock = await style == .widget ? ArchivedItem.singleLock : ArchivedItem.warmupLock

        await lock.takeTicket()

        defer {
            if Task.isCancelled {
                log(">>> Cancelled presentation task \(uuid.uuidString)")
            } else {
                log(">>> Finished presentation task \(uuid.uuidString)")
            }
            lock.returnTicket()
        }

        if Task.isCancelled {
            return nil
        }

        log(">>> New presentation task \(uuid.uuidString)")

        let topInfo = await prepareTopText()

        if Task.isCancelled {
            return nil
        }

        let bottomInfo = await prepareBottomText()

        if Task.isCancelled {
            return nil
        }

        let defaultColor = PresentationInfo.defaultCardColor
        var top = defaultColor
        var bottom = defaultColor
        var result: IMAGE?
        let (dm, status) = await (displayMode, status)

        if status.shouldDisplayLoading {
            // nothing to do for now

        } else if dm == .center || style != .square {
            result = await prepareImage(asThumbnail: style == .widget)
            if Task.isCancelled {
                return nil
            }

        } else if let img = await prepareImage(asThumbnail: false) {
            if Task.isCancelled {
                return nil
            }

            var processedImage: CIImage?
            let originalSize = img.size
            #if canImport(AppKit)
                if let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    processedImage = CIImage(cgImage: cgImage)
                } else {
                    processedImage = nil
                }
            #else
                processedImage = CIImage(image: img)
            #endif

            if var processedImage {
                if Task.isCancelled {
                    return nil
                }

                if expectedSize.width > 0, topInfo.willBeVisible || bottomInfo.willBeVisible {
                    let top = topInfo.expectedHeightEstimate(for: expectedSize, atTop: true)
                    let bottom = bottomInfo.expectedHeightEstimate(for: expectedSize, atTop: false)
                    if let withBlur = processedImage.applyLensEffect(top: top, bottom: bottom)?.cropped(to: CGRect(origin: .zero, size: originalSize)) {
                        processedImage = withBlur
                    }

                    if Task.isCancelled {
                        return nil
                    }
                }

                if topInfo.willBeVisible {
                    top = processedImage.calculateOuterColor(size: originalSize, top: true) ?? defaultColor

                    if Task.isCancelled {
                        return nil
                    }
                }

                if bottomInfo.willBeVisible {
                    bottom = processedImage.calculateOuterColor(size: originalSize, top: false) ?? defaultColor

                    if Task.isCancelled {
                        return nil
                    }
                }

                result = processedImage.asImage
            }
        }

        if Task.isCancelled {
            return nil
        }

        let p = await PresentationInfo(
            id: uuid,
            topText: topInfo,
            top: top,
            bottomText: bottomInfo,
            bottom: bottom,
            image: result,
            highlightColor: status.shouldDisplayLoading ? .none : highlightColor,
            hasFullImage: dm.prefersFullSizeImage,
            status: status,
            locked: isLocked,
            labels: labels,
            dominantTypeDescription: dominantTypeDescription
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
        if asThumbnail {
            return await thumbnail
        }

        if let bgItem = backgroundInfoObject {
            switch bgItem.content {
            case let .map(mapItem):
                let snapshotOptions = Images.SnapshotOptions(coordinate: mapItem.placemark.coordinate, range: 200, outputSize: imageDimensions)
                return try? await Images.mapSnapshot(with: snapshotOptions)

            case let .color(colour):
                return IMAGE.block(color: colour, size: CGSize(width: 1, height: 1))
            }
        }

        return await displayIcon
    }
}
