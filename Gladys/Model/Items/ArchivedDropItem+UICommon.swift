//
//  ArchivedDropItem+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CoreSpotlight

extension ArchivedDropItem {

	private static let mediumFormatter: DateFormatter = {
		let d = DateFormatter()
		d.doesRelativeDateFormatting = true
		d.dateStyle = .medium
		d.timeStyle = .medium
		return d
	}()

	var shouldDisplayLoading: Bool {
		return needsReIngest || loadingProgress != nil
	}

	var backgroundInfoObject: Any? {
		var currentItem: Any?
		var currentPriority = -1
		for item in typeItems {
			let (newItem, newPriority) = item.backgroundInfoObject
			if let newItem = newItem, newPriority > currentPriority {
				currentItem = newItem
				currentPriority = newPriority
			}
		}
		return currentItem
	}

	func delete() {
		isDeleting = true
		if cloudKitRecord != nil {
			CloudManager.markAsDeleted(uuid: uuid)
		} else {
			log("No cloud record for this item, skipping cloud delete")
		}
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uuid.uuidString]) { error in
			if let error = error {
				log("Error while deleting an index \(error)")
			}
		}
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
	}

	func renumberTypeItems() {
		var count = 0
		for i in typeItems {
			i.order = count
			count += 1
		}
	}

	func postModified() {
		NotificationCenter.default.post(name: .ItemModified, object: self)
	}

	var addedString: String {
		return ArchivedDropItem.mediumFormatter.string(from: createdAt) + "\n" + diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}
}
