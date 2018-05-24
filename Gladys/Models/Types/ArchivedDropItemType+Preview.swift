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
			return Model.temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString, isDirectory: false).appendingPathExtension(f)
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

			needsCleanup = blobPath != tempPath

			if needsCleanup {
				let fm = FileManager.default
				if !fm.fileExists(atPath: tempPath.path) {
					if let data = typeItem.dataForWrappedItem {
						try? data.write(to: tempPath)
						log("Created temporary file for preview: \(tempPath.path)")
					} else {
						try? fm.linkItem(at: blobPath, to: tempPath)
						log("Linked temporary file for preview: \(tempPath.path)")
					}
				}
				previewItemURL = tempPath
			} else {
				previewItemURL = blobPath
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
