import Combine
import Foundation
import GladysCommon
import SwiftUI

@MainActor
@Observable
public final class ArchivedItemWrapper: Identifiable {
    public let id = UUID()

    public init() {}

    public var hasItem: Bool {
        item != nil
    }

    public enum Style: Sendable {
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
    public var shade = false

    private weak var item: ArchivedItem?
    private var observer: Cancellable?

    public func clear() {
        if let i = item {
            i.cancelPresentationGeneration()
            item = nil
            observer?.cancel()
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

    public func configure(with newItem: ArchivedItem, size: CGSize, style: Style) {
        self.style = style
        cellSize = size

        if item == newItem {
            return
        }

        presentationInfo = PresentationInfo()
        item = newItem
        updatePresentationInfo(for: newItem, alwaysStartFresh: false)

        observer = newItem
            .itemUpdates
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePresentationInfo(for: newItem, alwaysStartFresh: true)
            }
    }

    private func updatePresentationInfo(for newItem: ArchivedItem, alwaysStartFresh: Bool) {
        Task {
            if alwaysStartFresh {
                await newItem.prepareForPresentationUpdate()
            }
            let size = CGSize(width: cellSize.width - Self.labelPadding(compact: cellSize.isCompact) * 2, height: cellSize.height)
            if let p = await newItem.createPresentationInfo(style: style, expectedSize: size) {
                if item?.uuid == p.itemId {
                    presentationInfo = p
                    labels = newItem.labels
                    status = newItem.status
                    flags = newItem.flags
                    locked = flags.contains(.needsUnlock)
                }
            }
        }
    }

    var shouldShowShadow: Bool {
        style.allowsShadows && presentationInfo.highlightColor == .none
    }

    private(set) var presentationInfo = PresentationInfo()

    func delete() {
        item?.delete()
    }

    // copied on presentation update
    var labels = [String]()
    var status: ArchivedItem.Status?
    var flags = ArchivedItem.Flags()
    var locked = false

    var dominantTypeDescription: String? {
        item?.dominantTypeDescription
    }

    private static let customPersonFormatStyle = PersonNameComponents.FormatStyle(style: .short)

    var shareOwnerDescription: String? {
        item?.cloudKitShareRecord?.owner.userIdentity.nameComponents?.formatted(ArchivedItemWrapper.customPersonFormatStyle)
    }

    var isShareWithOnlyOwner: Bool {
        item?.isShareWithOnlyOwner ?? false
    }

    var displayMode: ArchivedDropItemDisplayType {
        item?.displayMode ?? .fill
    }

    var shareMode: ArchivedItem.ShareMode {
        item?.shareMode ?? .none
    }

    public var accessibilityText: String {
        presentationInfo.accessibilityText
    }
}
