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
		if isWebURL {
			return Model.temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString, isDirectory: false).appendingPathExtension("webloc")
		} else if let f = fileExtension {
			return Model.temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString, isDirectory: false).appendingPathExtension(f)
		} else {
			return bytesPath
		}
	}
    
    final class PreviewCheckItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        let needsCleanup: Bool
        let parentUuid: UUID
        let uuid: UUID

        init(typeItem: ArchivedDropItemType) {

            parentUuid = typeItem.parentUuid
            uuid = typeItem.uuid

            let blobPath = typeItem.bytesPath
            let tempPath = typeItem.previewTempPath

            needsCleanup = blobPath != tempPath

            if needsCleanup {
                let fm = FileManager.default
                if !fm.fileExists(atPath: tempPath.path) {
                    try? Data().write(to: tempPath)
                    log("Placed check placeholder at \(tempPath.path)")
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
                    log("Removed check placeholder at \(previewItemURL.path)")
                }
            }
        }
    }

	final class PreviewItem: NSObject, QLPreviewItem {
		let previewItemURL: URL?
		let previewItemTitle: String?
		let needsCleanup: Bool
		let parentUuid: UUID
		let uuid: UUID

		init(typeItem: ArchivedDropItemType) {

			parentUuid = typeItem.parentUuid
			uuid = typeItem.uuid

			let blobPath = typeItem.bytesPath
			let tempPath = typeItem.previewTempPath

			needsCleanup = blobPath != tempPath

			if needsCleanup {
				let fm = FileManager.default
				if !fm.fileExists(atPath: tempPath.path) {
					if tempPath.pathExtension == "webloc", let url = typeItem.encodedUrl { // only happens on macOS, iOS uses another view for previewing
						try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .binary, options: 0).write(to: tempPath)
						log("Created temporary webloc for preview: \(tempPath.path)")
					} else if let data = typeItem.dataForDropping {
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
					log("Removed temporary preview at \(previewItemURL.path)")
				}
			}
		}
	}
}
