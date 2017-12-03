//
//  ArchivedDropItemType+Preview.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation
import QuickLook
import MobileCoreServices

extension ArchivedDropItemType: QLPreviewControllerDataSource {

	var previewTempPath: URL {
		if let f = fileExtension {
			return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gladys-preview-blob", isDirectory: false).appendingPathExtension(f)
		} else {
			return bytesPath
		}
	}

	func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
		return 1
	}

	func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
		return PreviewItem(typeItem: self)
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
					try? fm.linkItem(at: blobPath, to: tempPath)
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

	var canPreview: Bool {
		return typeIdentifier == "public.url" || typeIdentifier == "com.apple.webarchive" || QLPreviewController.canPreview(previewTempPath as NSURL)
	}

	var canAttach: Bool {
		return typeIdentifier != "public.url" && !typeConforms(to: kUTTypeText) && canPreview
	}
}
