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
}
