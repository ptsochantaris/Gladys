import Foundation
import SwiftUI

public struct PresentationInfo: Identifiable, Hashable {
    public enum FieldContent {
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

    public struct LabelInfo {
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

    public static func == (lhs: PresentationInfo, rhs: PresentationInfo) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
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

    public init(id: UUID, topText: FieldContent, top: COLOR, bottomText: FieldContent, bottom: COLOR, image: IMAGE?, highlightColor: ItemColor, hasFullImage: Bool) {
        self.id = id
        self.top = LabelInfo(content: topText, backgroundColor: top)
        self.bottom = LabelInfo(content: bottomText, backgroundColor: bottom)
        self.image = image
        self.highlightColor = highlightColor
        hasTransparentBackground = self.top.hasTransparentBackground || self.bottom.hasTransparentBackground
        self.hasFullImage = hasFullImage
        isPlaceholder = false
    }
}
