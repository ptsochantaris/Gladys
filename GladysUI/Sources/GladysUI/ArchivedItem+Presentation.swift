import Foundation
import GladysCommon
import MapKit
import Semalot
import SwiftUI

public extension ArchivedItem {
    private static let warmupLock = Semalot(tickets: UInt(ProcessInfo().processorCount))
    private static let singleLock = Semalot(tickets: 1)

    @MainActor
    func queueWarmup(style: ArchivedItemWrapper.Style) {
        log("Will (re)warm presentation for \(uuid)")

        let previous = warmingUp.associatedTask

        let task = Task<Void, Never>.detached { [weak self] in
            await previous?.value

            guard let self, let info = await createPresentationInfo(style: style) else { return }

            presentationInfoCache[uuid] = info

            Task { @MainActor [weak self] in
                if let self, !Task.isCancelled {
                    warmingUp = .done
                    objectWillChange.send()
                }
            }
        }
        warmingUp = .inProgress(task)
    }

    func createPresentationInfo(style: ArchivedItemWrapper.Style) async -> PresentationInfo? {
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
        let prepared = await prepareImage(asThumbnail: style == .widget)

        if Task.isCancelled {
            return nil
        }

        let fadeUsingImageColours = displayMode != .center
        let top = if fadeUsingImageColours, let prepared {
            prepared.calculateOuterColor(size: prepared.size, top: true) ?? PresentationInfo.defaultCardColor
        } else {
            PresentationInfo.defaultCardColor
        }

        if Task.isCancelled {
            return nil
        }

        let bottom = if fadeUsingImageColours, let prepared {
            prepared.calculateOuterColor(size: prepared.size, top: false) ?? PresentationInfo.defaultCardColor
        } else {
            PresentationInfo.defaultCardColor
        }

        if Task.isCancelled {
            return nil
        }

        return PresentationInfo(
            id: uuid,
            topText: topInfo,
            top: top,
            bottomText: bottomInfo,
            bottom: bottom,
            image: prepared,
            highlightColor: shouldDisplayLoading ? .none : highlightColor,
            hasFullImage: displayMode.prefersFullSizeImage
        )
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
