//
//  FileManager+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension FileManager {
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
                var data = Data(count: length)
                let result = getxattr(fileSystemPath, attributeName, &data, length, 0, 0)
                if result > 0, let dateString = String(data: data, encoding: .utf8), let time = TimeInterval(dateString) {
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
                let string = String(newValue.timeIntervalSinceReferenceDate)
                if var data = string.data(using: .utf8) {
                    let res = setxattr(fileSystemPath, attributeName, &data, data.count, 0, 0)
                    if res < 0 {
                        log(String(format: "Error while setting date attribute: %s for %s", strerror(errno), fileSystemPath!))
                    }
                }
            } else {
                removexattr(fileSystemPath, attributeName, 0)
            }
        }
    }
    
    private static let trueData = "true".data(using: .utf8)!
    private static let trueDataCount = trueData.count
    func setBoolAttribute(_ attributeName: String, at url: URL, to newValue: Bool) {
        guard fileExists(atPath: url.path) else {
            return
        }
        url.withUnsafeFileSystemRepresentation { fileSystemPath in
            if newValue {
                var bytes = FileManager.trueData
                let res = setxattr(fileSystemPath, attributeName, &bytes, FileManager.trueDataCount, 0, 0)
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
    
    func getUUIDAttribute(_ attributeName: String, from url: URL) -> UUID? {
        guard fileExists(atPath: url.path) else {
            return nil
        }
        
        return url.withUnsafeFileSystemRepresentation { fileSystemPath in
            if getxattr(fileSystemPath, attributeName, nil, 0, 0, 0) == 16 {
                var d = [UInt8](repeating: 0, count: 16)
                let result = getxattr(fileSystemPath, attributeName, &d, 16, 0, 0)
                if result > 0 {
                    return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]))
                }
            }
            return nil
        }
    }
    
    func setUUIDAttribute(_ attributeName: String, at url: URL, to uuid: UUID?) {
        guard fileExists(atPath: url.path) else {
            return
        }
        
        url.withUnsafeFileSystemRepresentation { fileSystemPath in
            if let u = uuid?.uuid {
                var bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
                let res = setxattr(fileSystemPath, attributeName, &bytes, 16, 0, 0)
                if res < 0 {
                    log(String(format: "Error while setting uuid attribute: %s for %s", strerror(errno), fileSystemPath!))
                }
            } else {
                removexattr(fileSystemPath, attributeName, 0)
            }
        }
    }
}
