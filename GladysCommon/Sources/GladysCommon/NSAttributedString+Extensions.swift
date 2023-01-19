import Foundation

public extension NSAttributedString {
    var toData: Data? {
        try? data(from: NSRange(location: 0, length: string.count), documentAttributes: [:])
    }
}

public extension String {
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
}
