import Foundation

public extension String {
    var filenameSafe: String {
        if let components = URLComponents(string: self) {
            if let host = components.host {
                return host + "-" + components.path.split(separator: "/").joined(separator: "-")
            } else {
                return components.path.split(separator: "/").joined(separator: "-")
            }
        } else {
            return replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "/", with: "-")
        }
    }

    var dropFilenameSafe: String {
        if let components = URLComponents(string: self) {
            if let host = components.host {
                return host + "-" + components.path.split(separator: "/").joined(separator: "-")
            } else {
                return components.path.split(separator: "/").joined(separator: "-")
            }
        } else {
            return replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
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
}
