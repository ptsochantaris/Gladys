import Combine
import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

public extension ArchivedItem {
    func prefetchPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) {
        if presentationPrefetchTask != nil {
            return
        }
        presentationPrefetchTask = Task.detached { [weak self] in
            guard let self else {
                return PresentationInfo()
            }
            let info = await createPresentationInfo(style: style, expectedSize: expectedSize, isPrefetch: true)
            Task { @MainActor in
                presentationPrefetchTask = nil
            }
            return info
        }
    }

    nonisolated func createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize, isPrefetch: Bool = false) async -> PresentationInfo {
        assert(!Thread.isMainThread)

        if !isPrefetch, let p = await presentationPrefetchTask {
            let info = await p.value
            if info.size == expectedSize {
                return info
            }
        }

        let topInfo = await prepareTopText()
        let bottomInfo = await prepareBottomText()

        let defaultColor = PresentationInfo.defaultCardColor
        var top = defaultColor
        var bottom = defaultColor
        var result: IMAGE?
        let (dm, status) = await (displayMode, status)

        if status.shouldDisplayLoading {
            // nothing to do for now

        } else if dm == .center || style != .square {
            result = await prepareImage(asThumbnail: style == .widget)

        } else if let img = await prepareImage(asThumbnail: false) {
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
                if expectedSize.width > 0, topInfo.willBeVisible || bottomInfo.willBeVisible {
                    let top = topInfo.expectedHeightEstimate(for: expectedSize, atTop: true)
                    let bottom = bottomInfo.expectedHeightEstimate(for: expectedSize, atTop: false)
                    if let withBlur = processedImage.applyLensEffect(top: top, bottom: bottom)?.cropped(to: CGRect(origin: .zero, size: originalSize)) {
                        processedImage = withBlur
                    }
                }

                result = processedImage.asImage

                let t1 = topInfo.willBeVisible
                let t2 = bottomInfo.willBeVisible

                if t1 || t2, let result, let cgImage = result.getCgImage() {
                    let wholeWidth = cgImage.width
                    let wholeHeight = cgImage.height
                    let dataLen = wholeWidth * wholeHeight * 4
                    let memory = calloc(1, dataLen)!
                    defer {
                        free(memory)
                    }

                    let context = createCgContext(data: memory, width: wholeWidth, height: wholeHeight)
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: wholeWidth, height: wholeHeight))

                    let rawData = UnsafeMutableRawBufferPointer(start: memory, count: dataLen)

                    if t1 {
                        top = await result.calculateOuterColor(size: originalSize, top: true, rawData: rawData) ?? defaultColor
                    }

                    if t2 {
                        bottom = await result.calculateOuterColor(size: originalSize, top: false, rawData: rawData) ?? defaultColor
                    }
                }
            }
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
            dominantTypeDescription: dominantTypeDescription,
            size: expectedSize
        )

        presentationInfoCache[uuid] = p

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

    private nonisolated func prepareImage(asThumbnail: Bool) async -> IMAGE? {
        assert(!Thread.isMainThread)

        if asThumbnail {
            return await thumbnail
        }

        if let bgItem = await backgroundInfoObject {
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
