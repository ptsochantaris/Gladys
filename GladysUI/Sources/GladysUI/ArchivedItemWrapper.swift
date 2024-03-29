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

    var cellSize = CGSize.zero
    var style = Style.square

    private weak var item: ArchivedItem?
    private var observer: Cancellable?

    @MainActor
    func clear() {
        if let i = item {
            i.presentationGenerator?.cancel()
            item = nil
            observer = nil
            presentationInfo = PresentationInfo()
        }
    }

    public static func labelPadding(compact: Bool) -> CGFloat {
        #if canImport(AppKit)
            10
        #else
            compact ? 9 : 14
        #endif
    }

    var labelSpacing: CGFloat {
        #if canImport(AppKit)
            4
        #else
            cellSize.isCompact ? 4 : 5
        #endif
    }

    @MainActor
    func configure(with newItem: ArchivedItem?, size: CGSize, style: Style) {
        guard let newItem else {
            clear()
            return
        }

        if let item, item != newItem {
            presentationInfo = PresentationInfo()
            if let p = item.presentationGenerator {
                p.cancel()
            }
        }

        self.style = style
        cellSize = size
        item = newItem
        updatePresentationInfo(for: newItem, alwaysStartFresh: false)

        observer = newItem
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePresentationInfo(for: newItem, alwaysStartFresh: true)
            }
    }

    @MainActor private func updatePresentationInfo(for newItem: ArchivedItem, alwaysStartFresh: Bool) {
        if alwaysStartFresh, let p = newItem.presentationGenerator {
            p.cancel()
        }
        Task {
            if let p = await newItem.createPresentationInfo(style: style, expectedSize: CGSize(width: cellSize.width - Self.labelPadding(compact: cellSize.isCompact) * 2, height: cellSize.height)) {
                if item?.uuid == p.id {
                    presentationInfo = p
                }
            }
        }
    }

    @MainActor
    var shouldShowShadow: Bool {
        style.allowsShadows && presentationInfo.highlightColor == .none
    }

    @MainActor
    @Published var presentationInfo = PresentationInfo()

    @MainActor
    func delete() {
        item?.delete()
    }

    @MainActor
    var labels: [String] {
        item?.labels ?? []
    }

    @MainActor
    var status: ArchivedItem.Status? {
        item?.status
    }

    @MainActor
    var dominantTypeDescription: String? {
        item?.dominantTypeDescription
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
        if let status, status.shouldDisplayLoading {
            if status == .isBeingIngested(nil) {
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

        #if canImport(UIKit)
            if let v = presentationInfo.image?.accessibilityValue {
                components.append(v)
            }
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
