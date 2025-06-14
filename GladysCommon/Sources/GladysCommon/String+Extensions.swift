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

    func height(for width: CGFloat, lineLimit: Int) -> CGFloat {
        #if os(visionOS)
            let font = FONT.preferredFont(forTextStyle: FONT.TextStyle.body)
        #else
            let font = FONT.preferredFont(forTextStyle: FONT.TextStyle.caption1)
        #endif

        let maxHeight = CGFloat(lineLimit) * font.lineHeight + (CGFloat(lineLimit - 1) * font.leading)

        let attributedText = NSAttributedString(string: self, attributes: [.font: font])
        let frameSetter = CTFramesetterCreateWithAttributedString(attributedText)
        let guide = CGSize(width: width, height: maxHeight)
        let result = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, CFRangeMake(0, 0), nil, guide, nil)
        return result.height
    }
}
