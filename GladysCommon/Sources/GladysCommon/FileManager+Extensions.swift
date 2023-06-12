import Foundation

public extension FileManager {
    func contentSizeOfDirectory(at directoryURL: URL) -> Int64 {
        var contentSize: Int64 = 0
        if let e = enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for itemURL in e {
                if let itemURL = itemURL as? URL {
                    let s = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                    contentSize += Int64(s ?? 0)
                }
            }
        }
        return contentSize
    }

    func moveAndReplaceItem(at: URL, to: URL) throws {
        if fileExists(atPath: to.path) {
            try removeItem(at: to)
        }
        try moveItem(at: at, to: to)
    }

    func copyAndReplaceItem(at: URL, to: URL) throws {
        if fileExists(atPath: to.path) {
            try removeItem(at: to)
        }
        try copyItem(at: at, to: to)
    }

    func getDateAttribute(_ attributeName: String, from url: URL) -> Date? {
        guard fileExists(atPath: url.path) else {
            return nil
        }

        return url.withUnsafeFileSystemRepresentation { fileSystemPath in
            let length = getxattr(fileSystemPath, attributeName, nil, 0, 0, 0)
            if length > 0 {
                var data = [UInt8](repeating: 0, count: length)
                let result = getxattr(fileSystemPath, attributeName, &data, length, 0, 0)
                if result > 0, let dateString = String(bytes: data, encoding: .utf8), let time = TimeInterval(dateString) {
                    return Date(timeIntervalSinceReferenceDate: time)
                }
            }
            return nil
        }
    }

    func setDateAttribute(_ attributeName: String, at url: URL, to date: Date?) {
        guard fileExists(atPath: url.path) else {
            return
        }

        url.withUnsafeFileSystemRepresentation { fileSystemPath in
            if let newValue = date {
                String(newValue.timeIntervalSinceReferenceDate).utf8CString.withUnsafeBytes { bytes in
                    if setxattr(fileSystemPath, attributeName, bytes.baseAddress!, bytes.count, 0, 0) < 0 {
                        log(String(format: "Error while setting date attribute: %s for %s", strerror(errno), fileSystemPath!))
                    }
                }
            } else {
                removexattr(fileSystemPath, attributeName, 0)
            }
        }
    }

    func setBoolAttribute(_ attributeName: String, at url: URL, to newValue: Bool) {
        guard fileExists(atPath: url.path) else {
            return
        }
        url.withUnsafeFileSystemRepresentation { fileSystemPath in
            if newValue {
                var bytes: [UInt8] = [116, 114, 117, 101]
                let res = setxattr(fileSystemPath, attributeName, &bytes, 4, 0, 0)
                if res < 0 {
                    log(String(format: "Error while setting bool attribute: %s for %s", strerror(errno), fileSystemPath!))
                }
            } else {
                removexattr(fileSystemPath, attributeName, 0)
            }
        }
    }

    func getBoolAttribute(_ attributeName: String, from url: URL) -> Bool? {
        guard fileExists(atPath: url.path) else {
            return nil
        }
        return url.withUnsafeFileSystemRepresentation { fileSystemPath in
            let length = getxattr(fileSystemPath, attributeName, nil, 0, 0, 0)
            return length > 0
        }
    }
}
