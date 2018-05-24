//
//  ArchivedDropItemType+Preview.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

#if os(iOS)
import QuickLook
#else
import Quartz
#endif

extension ArchivedDropItemType {

	var previewTempPath: URL {
		if let f = fileExtension {
			return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid.uuidString, isDirectory: false).appendingPathExtension(f)
		} else {
			return bytesPath
		}
	}

	class PreviewItem: NSObject, QLPreviewItem {
		let previewItemURL: URL?
		let previewItemTitle: String?
		let needsCleanup: Bool

		init(typeItem: ArchivedDropItemType) {

			let blobPath = typeItem.bytesPath
			let tempPath = typeItem.previewTempPath

			if blobPath == tempPath {
				previewItemURL = blobPath
				needsCleanup = false
			} else {
				let fm = FileManager.default
				if fm.fileExists(atPath: tempPath.path) {
					try? fm.removeItem(at: tempPath)
				}

				if let data = typeItem.dataForWrappedItem {
					try? data.write(to: tempPath)
				} else {
					try? fm.createSymbolicLink(at: tempPath, withDestinationURL: blobPath)
				}
				log("Created temporary file for preview")
				previewItemURL = tempPath
				needsCleanup = true
			}

			previewItemTitle = typeItem.oneTitle
		}

		deinit {
			if needsCleanup, let previewItemURL = previewItemURL {
				let fm = FileManager.default
				if fm.fileExists(atPath: previewItemURL.path) {
					try? fm.removeItem(at: previewItemURL)
					log("Removed temporary file for preview")
				}
			}
		}
	}
}
