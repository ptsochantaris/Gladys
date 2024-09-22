import Foundation
import SwiftUI
#if os(iOS) || os(visionOS)
    import UIKit
#endif

@MainActor
public struct PresentationInfo: Identifiable, Hashable, Sendable {
    public enum FieldContent: Sendable {
        case none, text(String), link(URL), note(String), hint(String)

        public var willBeVisible: Bool {
            switch self {
            case .none: false
            case .hint, .link, .note, .text: true
            }
        }

        public var rawText: String? {
            switch self {
            case .none: nil
            case let .link(url): url.absoluteString
            case let .hint(text), let .note(text), let .text(text): text
            }
        }

        public func expectedHeightEstimate(for size: CGSize, atTop: Bool) -> CGFloat? {
            guard willBeVisible else { return nil }

            let height: CGFloat = switch self {
            case .none:
                0
            case .link:
                39
            case let .hint(text), let .note(text), let .text(text):
                min(92, text.height(for: size.width, lineLimit: lineLimit(isTop: atTop, size: size)) + 30)
            }

            return height / size.height
        }

        public func lineLimit(isTop: Bool, size: CGSize) -> Int {
            switch self {
            case .hint, .note:
                4
            case .link, .none:
                1
            case .text:
                isTop ? (size.isCompact ? 2 : 4) : 2
            }
        }
    }

    @MainActor
    public struct LabelInfo: Sendable {
        public let content: FieldContent
        public let backgroundColor: Color
        public let isBright: Bool
        public let hasTransparentBackground: Bool

        init(content: FieldContent, backgroundColor: COLOR) {
            self.content = content
            self.backgroundColor = Color(backgroundColor)
            #if os(visionOS)
                if backgroundColor == UIColor.systemFill {
                    isBright = false
                } else {
                    isBright = backgroundColor.isBright
                }
            #else
                isBright = backgroundColor.isBright
            #endif
            let cg = backgroundColor.cgColor
            hasTransparentBackground = cg == Color.clear.cgColor
        }

        init() {
            content = .none
            backgroundColor = Color(PresentationInfo.defaultCardColor)
            isBright = PresentationInfo.defaultCardIsBright
            hasTransparentBackground = true
        }
    }

    public let id: UUID
    public let top: LabelInfo
    public let bottom: LabelInfo
    public let image: IMAGE?
    public let highlightColor: ItemColor
    public let hasTransparentBackground: Bool
    public let hasFullImage: Bool
    public let isPlaceholder: Bool
    public let accessibilityText: String

    public nonisolated static func == (lhs: PresentationInfo, rhs: PresentationInfo) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public init() {
        id = UUID()
        top = LabelInfo()
        bottom = LabelInfo()
        image = nil
        highlightColor = .none
        hasTransparentBackground = top.hasTransparentBackground || bottom.hasTransparentBackground
        hasFullImage = false
        isPlaceholder = true
        accessibilityText = ""
    }

    public static func placeholders(count: Int) -> [PresentationInfo] {
        (0 ..< count).map { _ in
            PresentationInfo()
        }
    }

    public static let defaultShadow = Color.black
    #if os(visionOS)
        public static let defaultCardColor = UIColor.systemFill
        private static var defaultCardIsBright = false
    #else
        public static let defaultCardColor = COLOR.g_colorMacCard
        private static var defaultCardIsBright: Bool { defaultCardColor.isBright } // must be dynamic
    #endif

    public init(id: UUID, topText: FieldContent, top: COLOR, bottomText: FieldContent, bottom: COLOR, image: IMAGE?, highlightColor: ItemColor, hasFullImage: Bool, status: ArchivedItem.Status, locked: Bool, labels: [String]?, dominantTypeDescription: String?) {
        self.id = id
        self.top = LabelInfo(content: topText, backgroundColor: top)
        self.bottom = LabelInfo(content: bottomText, backgroundColor: bottom)
        self.image = image
        self.highlightColor = highlightColor
        hasTransparentBackground = self.top.hasTransparentBackground || self.bottom.hasTransparentBackground
        self.hasFullImage = hasFullImage
        isPlaceholder = false

        if status.shouldDisplayLoading {
            if status == .isBeingIngested(nil) {
                accessibilityText = "Importing item. Activate to cancel."
            } else {
                accessibilityText = "Processing item."
            }

        } else if locked {
            accessibilityText = "Item Locked"

        } else {
            var components = [String]()

            if let topText = topText.rawText, topText.isPopulated {
                components.append(topText)
            }

            if let dominantTypeDescription {
                components.append(dominantTypeDescription)
            }

            #if os(iOS) || os(visionOS)
                if let v = image?.accessibilityValue {
                    components.append(v)
                }
            #endif

            if PersistedOptions.displayLabelsInMainView, let l = labels, !l.isEmpty {
                components.append(l.joined(separator: ", "))
            }

            if let l = bottomText.rawText, l.isPopulated {
                components.append(l)
            }

            accessibilityText = components.joined(separator: "\n")
        }
    }
}
