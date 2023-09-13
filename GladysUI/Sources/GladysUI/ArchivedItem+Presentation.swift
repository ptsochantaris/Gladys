import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

public extension ArchivedItem {
    private static let warmupLock = Semalot(tickets: UInt(ProcessInfo().processorCount))

    @MainActor
    func queueWarmup() {
        log("Will (re)warm presentation for \(uuid)")

        let previous = warmingUp.associatedTask

        let task = Task<Void, Never>.detached { [weak self] in
            await previous?.value
            await self?.warmUp()
        }
        warmingUp = .inProgress(task)
    }

    private func warmUp() async {
        if Task.isCancelled {
            return
        }

        await ArchivedItem.warmupLock.takeTicket()
        defer {
            ArchivedItem.warmupLock.returnTicket()
        }

        if Task.isCancelled {
            return
        }

        assert(!Thread.isMainThread)

        let topInfo = prepareTopText()
        let bottomInfo = prepareBottomText()
        let prepared = await prepareImage()

        if Task.isCancelled {
            return
        }

        let fadeUsingImageColours = displayMode != .center
        let top = if fadeUsingImageColours, let prepared {
            prepared.calculateOuterColor(size: prepared.size, top: true) ?? PresentationInfo.defaultCardColor
        } else {
            PresentationInfo.defaultCardColor
        }

        if Task.isCancelled {
            return
        }

        let bottom = if fadeUsingImageColours, let prepared {
            prepared.calculateOuterColor(size: prepared.size, top: false) ?? PresentationInfo.defaultCardColor
        } else {
            PresentationInfo.defaultCardColor
        }

        if Task.isCancelled {
            return
        }

        presentationInfoCache[uuid] =
            PresentationInfo(topText: topInfo,
                             top: top,
                             bottomText: bottomInfo,
                             bottom: bottom,
                             image: prepared,
                             highlightColor: highlightColor)

        Task { @MainActor in
            if Task.isCancelled {
                return
            }
            warmingUp = .done
            objectWillChange.send()
        }
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
        } else if PersistedOptions.displayNotesInMainView, !note.isEmpty {
            .note(note)
        } else if let url = associatedWebURL, backgroundInfoObject == nil {
            .link(url)
        } else {
            .none
        }
    }

    private func prepareImage() async -> IMAGE? {
        assert(!Thread.isMainThread)

        let cacheKey = imageCacheKey
        if let existing = Images.shared[cacheKey] {
            return existing
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
                result = await displayIcon.byPreparingForDisplay()
            #endif
        }
        if let result {
            Images.shared[cacheKey] = result
        }
        return result
    }
}
