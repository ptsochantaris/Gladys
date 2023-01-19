import Foundation

extension NSAttributedString {
    public var toData: Data? {
        try? data(from: NSRange(location: 0, length: string.count), documentAttributes: [:])
    }
}

extension String {
    public func truncate(limit: Int) -> String {
        let string = self
        if string.count > limit {
            let s = string.startIndex
            let e = string.index(string.startIndex, offsetBy: limit)
            return String(string[s ..< e])
        }
        return string
    }

    public func truncateWithEllipses(limit: Int) -> String {
        let string = self
        let limit = limit - 1
        if string.count > limit {
            let s = string.startIndex
            let e = string.index(string.startIndex, offsetBy: limit)
            return String(string[s ..< e].appending("…"))
        }
        return string
    }
}
