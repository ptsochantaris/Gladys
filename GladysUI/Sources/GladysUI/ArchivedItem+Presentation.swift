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
            return existing

        } else if let presentationGenerator, !presentationGenerator.isCancelled {
            log(">>> Deduped presentation task \(uuid.uuidString)")
            return await presentationGenerator.value

        } else {
            let newTask = Task.detached { [weak self] in await self?._createPresentationInfo(style: style, expectedSize: expectedSize) }
            presentationGenerator = newTask
            defer {
                presentationGenerator = nil
            }
            return await newTask.value
        }
    }

    private nonisolated func _createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        log(">>> New presentation task \(uuid.uuidString)")
        defer {
            if Task.isCancelled {
                log(">>> Cancelled presentation task \(uuid.uuidString)")
            } else {
                log(">>> Finished presentation task \(uuid.uuidString)")
            }
        }

        if Task.isCancelled {
            return nil
        }

        let lock = await style == .widget ? ArchivedItem.singleLock : ArchivedItem.warmupLock
        await lock.takeTicket()
        defer {
            lock.returnTicket()
        }

        if Task.isCancelled {
            return nil
        }

        assert(!Thread.isMainThread)

        let topInfo = await prepareTopText()

        if Task.isCancelled {
            return nil
        }

        let bottomInfo = await prepareBottomText()

        if Task.isCancelled {
            return nil
        }

        var top = PresentationInfo.defaultCardColor
        var bottom = PresentationInfo.defaultCardColor
        var result: IMAGE?

        let dm = await displayMode
        if dm == .center || style != .square {
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
                    processedImage = CIImage(cgImage: cgImage, options: [.nearestSampling: true])
                } else {
                    processedImage = nil
                }
            #else
                processedImage = CIImage(image: img, options: [.nearestSampling: true])
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
                    top = processedImage.calculateOuterColor(size: originalSize, top: true) ?? PresentationInfo.defaultCardColor

                    if Task.isCancelled {
                        return nil
                    }
                }

                if bottomInfo.willBeVisible {
                    bottom = processedImage.calculateOuterColor(size: originalSize, top: false) ?? PresentationInfo.defaultCardColor

                    if Task.isCancelled {
                        return nil
                    }
                }

                result = processedImage.asImage
            }
        }

        let highlight = await status.shouldDisplayLoading ? .none : highlightColor

        let p = PresentationInfo(
            id: uuid,
            topText: topInfo,
            top: top,
            bottomText: bottomInfo,
            bottom: bottom,
            image: result,
            highlightColor: highlight,
            hasFullImage: dm.prefersFullSizeImage
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
