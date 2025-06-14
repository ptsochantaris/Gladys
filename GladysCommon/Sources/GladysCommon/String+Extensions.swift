import Foundation
import SwiftUI

public extension String {
    static func fromUTF8Data(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    var filenameSafe: String {
        if let components = URLComponents(string: self) {
            if let host = components.host {
                host + "-" + components.path.split(separator: "/").joined(separator: "-")
            } else {
                components.path.split(separator: "/").joined(separator: "-")
            }
        } else {
            replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "/", with: "-")
        }
    }

    var dropFilenameSafe: String {
        if let components = URLComponents(string: self) {
            if let host = components.host {
                host + "-" + components.path.split(separator: "/").joined(separator: "-")
            } else {
                components.path.split(separator: "/").joined(separator: "-")
            }
        } else {
            replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        }
    }

    func truncate(limit: Int) -> String {
        let string = self
        if string.count > limit {
            let s = string.startIndex
            let e = string.index(string.startIndex, offsetBy: limit)
            return String(string[s ..< e])
        }
        return string
    }

    func truncateWithEllipses(limit: Int) -> String {
        let string = self
        let limit = limit - 1
        if string.count > limit {
            let s = string.startIndex
            let e = string.index(string.startIndex, offsetBy: limit)
            return String(string[s ..< e].appending("…"))
        }
        return string
    }

    func height(for containerSize: CGSize, lineLimit: Int) -> CGFloat {
        #if os(visionOS)
            let font = FONT.preferredFont(forTextStyle: FONT.TextStyle.body)
        #else
            let font = FONT.preferredFont(forTextStyle: FONT.TextStyle.caption1)
        #endif

        let attributedText = NSAttributedString(string: self, attributes: [.font: font])
        let frameSetter = CTFramesetterCreateWithAttributedString(attributedText)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, CFRangeMake(0, 0), nil, containerSize, nil)
        let ctFRame = CTFramesetterCreateFrame(frameSetter,
                                               CFRange(location: 0, length: count),
                                               CGPath(rect: CGRect(origin: .zero, size: suggestedSize), transform: nil),
                                               nil)

        let lines = CTFrameGetLines(ctFRame) as! [CTLine]
        guard let lastLine = lines.prefix(lineLimit).last else {
            return 10
        }
        let lastLineRange = CTLineGetStringRange(lastLine)
        let maxCount = lastLineRange.location + lastLineRange.length
        let visibleRange = CFRangeMake(0, maxCount)

        let height = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, visibleRange, nil, containerSize, nil).height
        #if canImport(AppKit)
        return height + 2
        #else
        return height + 14
        #endif
    }
}
