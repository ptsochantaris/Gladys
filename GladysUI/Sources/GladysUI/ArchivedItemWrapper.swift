import Combine
import Foundation
import GladysCommon
import SwiftUI

@MainActor
public final class Grouper<T: Sendable> {
    private let (stream, continuation) = AsyncStream.makeStream(of: T.self)
    private var count = 0

    public init() {}

    public func queue(_ element: T) {
        count += 1
        continuation.yield(element)
    }

    public func nextBatch() async -> [T]? {
        var res = [T]()
        for await element in stream {
            res.append(element)
            count -= 1
            if count == 0 {
                return res
            }
        }
        return nil
    }

    public func shutdown() {
        continuation.finish()
    }
}

@MainActor
@Observable
public final class ArchivedItemWrapper: Identifiable {
    public let id = UUID()

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

    private enum UpdateRequest: Equatable {
        case update(ArchivedItem, Bool), clear, add(ArchivedItem, CGSize, Style)

        var isReset: Bool {
            switch self {
            case .add, .update: false
            case .clear: true
            }
        }

        var relatedItem: ArchivedItem? {
            switch self {
            case let .add(archivedItem, _, _), let .update(archivedItem, _):
                archivedItem
            case .clear:
                nil
            }
        }
    }

    private let updateQueue = Grouper<UpdateRequest>()

    public func configure(with newItem: ArchivedItem, size: CGSize, style: Style) {
        updateQueue.queue(.add(newItem, size, style))
    }

    public func clear() {
        updateQueue.queue(.clear)
    }

    private func processUpdateRequest(updateRequest: UpdateRequest) async {
        switch updateRequest {
        case let .update(queuedItem, ignoreCache):
            await updatePresentationInfo(ignoreCache: ignoreCache, queuedItem: queuedItem)

        case let .add(newItem, size, style):
            self.style = style
            cellSize = size
            item = newItem
            updateQueue.queue(.update(newItem, false))

            observer = newItem
                .itemUpdates
                .sink { [weak self] _ in
                    self?.updateQueue.queue(.update(newItem, true))
                }

        case .clear:
            observer?.cancel()
            observer = nil
            item = nil

            presentationInfo = PresentationInfo()
            labels = []
            flags = ArchivedItem.Flags()
            locked = false
            status = .nominal
        }
    }

    public init() {
        Task {
            while var updateRequests = await updateQueue.nextBatch() {
                if let clearIndex = updateRequests.lastIndex(where: { $0.isReset }), clearIndex > 0 {
                    updateRequests[0 ..< clearIndex] = []
                }
                for request in updateRequests {
                    await processUpdateRequest(updateRequest: request)
                }
            }
        }
    }

    private func updatePresentationInfo(ignoreCache: Bool, queuedItem: ArchivedItem) async {
        guard item?.uuid == queuedItem.uuid else {
            return
        }

        var generateNewInfo = true
        if let cached = presentationInfoCache[queuedItem.uuid] {
            if ignoreCache {
                presentationInfoCache[queuedItem.uuid] = nil
            } else {
                presentationInfo = cached
                generateNewInfo = false
            }
        }

        if generateNewInfo {
            let size = CGSize(width: cellSize.width - Self.labelPadding(compact: cellSize.isCompact) * 2, height: cellSize.height)
            let p = await queuedItem.createPresentationInfo(style: style, expectedSize: size)

            guard item?.uuid == queuedItem.uuid else {
                return
            }

            presentationInfo = p
        }

        labels = queuedItem.labels
        flags = queuedItem.flags
        locked = flags.contains(.needsUnlock)
        status = queuedItem.status
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
