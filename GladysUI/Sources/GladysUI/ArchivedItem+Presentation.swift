import Combine
import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

@MainActor private class PresentationGenerator {
    private struct Operation: Hashable {
        let uuid: UUID
        let block: @Sendable () async -> PresentationInfo?

        let publisher = PassthroughSubject<PresentationInfo?, Never>()

        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.uuid == rhs.uuid
        }

        func go() async {
            let item = await block()
            publisher.send(item)
        }

        @MainActor
        var result: PresentationInfo? {
            get async {
                for await value in publisher.values {
                    return value
                }
                return nil
            }
        }
    }

    private let arrival = CurrentValueSubject<Void, Never>(())

    private var queuedItems = [Operation]() {
        didSet {
            log(">>> queuedItems count: \(queuedItems.count)")
        }
    }

    private var activeOperations = [Operation]() {
        didSet {
            log(">>> activeOperations count: \(activeOperations.count)")
        }
    }

    func waitIfNeeded(for uuid: UUID) async -> PresentationInfo? {
        let item = queuedItems.first(where: { $0.uuid == uuid }) ?? activeOperations.first(where: { $0.uuid == uuid })
        return await item?.result
    }

    private static func countOptimalCores() -> UInt {
        var coreCount: Int32 = 0
        var len = MemoryLayout.size(ofValue: coreCount)
        var result = sysctlbyname("hw.perflevel0.physicalcpu", &coreCount, &len, nil, 0)
        if result == 0 {
            return UInt(coreCount)
        }

        // fall back to plain CPU count
        result = sysctlbyname("hw.physicalcpu", &coreCount, &len, nil, 0)
        if result == 0 {
            return UInt(coreCount)
        }

        // Can't access the count, play it safe
        return 1
    }

    private let semalot = {
        let bundlePathExtension = Bundle.main.bundleURL.pathExtension
        let isAppex = bundlePathExtension == "appex"
        let count: UInt = isAppex
            ? 1
            : PresentationGenerator.countOptimalCores()

        log("Semalot count for presentation operations: \(count)")
        return Semalot(tickets: count)
    }()

    init() {
        let iterator = arrival.values
        Task {
            for await _ in iterator {
                while queuedItems.isPopulated {
                    await semalot.takeTicket()
                    guard let nextItem = queuedItems.popLast() else {
                        semalot.returnTicket()
                        continue
                    }
                    activeOperations.insert(nextItem, at: 0)
                    let uuid = nextItem.uuid
                    Task.detached(priority: .userInitiated) { [weak self] in
                        await nextItem.go()
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            activeOperations.removeAll { $0.uuid == uuid }
                            semalot.returnTicket()
                        }
                    }
                }
            }
        }
    }

    func queue(uuid: UUID, block: @Sendable @escaping () async -> PresentationInfo?) {
        queuedItems.insert(Operation(uuid: uuid, block: block), at: 0)
        arrival.send()
    }

    func cancel(uuid: UUID) {
        queuedItems.removeAll { $0.uuid == uuid }
    }
}

@MainActor
private let presentationGenerator = PresentationGenerator()

public extension ArchivedItem {
    func prefetchPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) {
        if presentationInfoCache[uuid] != nil {
            return
        }

        presentationGenerator.queue(uuid: uuid) { [weak self] in
            await self?._createPresentationInfo(style: style, expectedSize: expectedSize)
        }
    }

    func ignorePresentationPrefetch() {
        presentationGenerator.cancel(uuid: uuid)
    }

    @discardableResult
    func createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        if let existing = presentationInfoCache[uuid] {
            log(">>> Using cached presentation info for \(uuid.uuidString)")
            return existing
        }

        presentationGenerator.queue(uuid: uuid) { [weak self] in
            await self?._createPresentationInfo(style: style, expectedSize: expectedSize)
        }

        return await presentationGenerator.waitIfNeeded(for: uuid)
    }

    func cancelPresentationGeneration() {
        presentationGenerator.cancel(uuid: uuid)
    }

    func prepareForPresentationUpdate() async {
        cancelPresentationGeneration()
        _ = await presentationGenerator.waitIfNeeded(for: uuid)
        presentationInfoCache[uuid] = nil
    }

    private nonisolated func _createPresentationInfo(style: ArchivedItemWrapper.Style, expectedSize: CGSize) async -> PresentationInfo? {
        assert(!Thread.isMainThread)

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

                if topInfo.willBeVisible {
                    top = processedImage.calculateOuterColor(size: originalSize, top: true) ?? defaultColor
                }

                if bottomInfo.willBeVisible {
                    bottom = processedImage.calculateOuterColor(size: originalSize, top: false) ?? defaultColor
                }

                result = processedImage.asImage
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
            dominantTypeDescription: dominantTypeDescription
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
