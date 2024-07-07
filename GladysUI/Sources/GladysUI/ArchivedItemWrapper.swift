import Combine
import Foundation
import GladysCommon
import SwiftUI

@MainActor
@Observable
public final class ArchivedItemWrapper: Identifiable {
    private let emptyId = UUID()

    public nonisolated var id: UUID {
        MainActor.assumeIsolated {
            item?.uuid ?? emptyId
        }
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
            .itemUpdates
            .sink { [weak self] _ in
                self?.updatePresentationInfo(for: newItem, alwaysStartFresh: true)
            }
    }

    private func updatePresentationInfo(for newItem: ArchivedItem, alwaysStartFresh: Bool) {
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

    var shouldShowShadow: Bool {
        style.allowsShadows && presentationInfo.highlightColor == .none
    }

    var presentationInfo = PresentationInfo()

    func delete() {
        item?.delete()
    }

    var labels: [String] {
        item?.labels ?? []
    }

    var status: ArchivedItem.Status? {
        item?.status
    }

    var dominantTypeDescription: String? {
        item?.dominantTypeDescription
    }

    var shareOwnerDescription: String? {
        item?.cloudKitShareRecord?.owner.userIdentity.description
    }

    var isShareWithOnlyOwner: Bool {
        item?.isShareWithOnlyOwner ?? false
    }

    var flags: ArchivedItem.Flags {
        item?.flags ?? []
    }

    var displayMode: ArchivedDropItemDisplayType {
        item?.displayMode ?? .fill
    }

    var shareMode: ArchivedItem.ShareMode {
        item?.shareMode ?? .none
    }

    var locked: Bool {
        item?.flags.contains(.needsUnlock) ?? false
    }

    public var accessibilityText: String {
        presentationInfo.accessibilityText
    }
}
