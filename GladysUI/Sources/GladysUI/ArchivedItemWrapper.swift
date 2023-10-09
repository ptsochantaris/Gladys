import Combine
import Foundation
import GladysCommon
import SwiftUI

public final class ArchivedItemWrapper: ObservableObject, Identifiable {
    private let emptyId = UUID()

    public var id: UUID {
        item?.uuid ?? emptyId
    }

    public var hasItem: Bool {
        item != nil
    }

    public enum Style {
        case square, widget, wide

        var allowsLabels: Bool {
            switch self {
            case .square, .wide: true
            case .widget: false
            }
        }

        var allowsShadows: Bool {
            switch self {
            case .square: true
            case .wide, .widget: false
            }
        }
    }

    var compact = false
    var cellSize = CGSize.zero
    var style = Style.square

    private weak var item: ArchivedItem?
    private var observer: Cancellable?

    @MainActor
    func clear() {
        item = nil
        objectWillChange.send()
    }

    @MainActor
    func configure(with newItem: ArchivedItem?, size: CGSize, style: Style) {
        guard let newItem else { return }
        if newItem.uuid == item?.uuid, size.width == cellSize.width, style == self.style {
            return
        }

        self.style = style
        cellSize = size
        compact = cellSize.width < 170
        item = newItem
        observer = newItem
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                ensureItemIsWarmedUp()
            }

        ensureItemIsWarmedUp()
    }

    @MainActor
    private func ensureItemIsWarmedUp() {
        guard let item else { return }

        assert(Thread.isMainThread)

        switch item.warmingUp {
        case let .inProgress(existing):
            existing.cancel()
            item.warmingUp = .pending
        case .done:
            if presentationInfoCache[item.uuid] != nil {
                objectWillChange.send()
                return
            }
            item.warmingUp = .pending
        case .pending:
            break
        }

        item.queueWarmup(style: style)
    }

    @MainActor
    var shouldShowShadow: Bool {
        style.allowsShadows && presentationInfo.highlightColor == .none
    }

    @MainActor
    var isFirstImport: Bool {
        guard let item else {
            return false
        }
        return item.shouldDisplayLoading && !(item.needsReIngest || item.flags.contains(.isBeingCreatedBySync))
    }

    @MainActor
    var presentationInfo: PresentationInfo {
        if let uuid = item?.uuid, let existing = presentationInfoCache[uuid] {
            return existing
        }
        return PresentationInfo()
    }

    @MainActor
    func delete() {
        item?.delete()
    }

    @MainActor
    var labels: [String] {
        item?.labels ?? []
    }

    @MainActor
    var loadingProgress: Progress? {
        item?.loadingProgress
    }

    @MainActor
    var dominantTypeDescription: String? {
        item?.dominantTypeDescription
    }

    @MainActor var shouldDisplayLoading: Bool {
        item?.shouldDisplayLoading ?? false
    }

    @MainActor
    var shareOwnerDescription: String? {
        item?.cloudKitShareRecord?.owner.userIdentity.description
    }

    @MainActor
    var isShareWithOnlyOwner: Bool {
        item?.isShareWithOnlyOwner ?? false
    }

    @MainActor
    var flags: ArchivedItem.Flags {
        item?.flags ?? []
    }

    @MainActor
    var displayMode: ArchivedDropItemDisplayType {
        item?.displayMode ?? .fill
    }

    @MainActor
    var shareMode: ArchivedItem.ShareMode {
        item?.shareMode ?? .none
    }

    @MainActor
    var locked: Bool {
        item?.flags.contains(.needsUnlock) ?? false
    }

    @MainActor
    public var accessibilityText: String {
        if shouldDisplayLoading {
            if isFirstImport {
                return "Importing item. Activate to cancel."
            } else {
                return "Processing item."
            }
        }

        if locked {
            return "Item Locked"
        }

        var components = [String?]()

        if let topText = presentationInfo.top.content.rawText, topText.isPopulated {
            components.append(topText)
        }

        components.append(dominantTypeDescription)

        let image = presentationInfo.image
        #if canImport(UIKit)
        components.append(image?.accessibilityLabel)
        components.append(image?.accessibilityValue)
        #endif

        if PersistedOptions.displayLabelsInMainView, let l = item?.labels, !l.isEmpty {
            components.append(l.joined(separator: ", "))
        }

        if let l = presentationInfo.bottom.content.rawText, l.isPopulated {
            components.append(l)
        }

        return components.compactMap { $0 }.joined(separator: "\n")
    }
}
