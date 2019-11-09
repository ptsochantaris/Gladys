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

	func removeFromCloudkit() {
		cloudKitRecord = nil
		cloudKitShareRecord = nil
		for typeItem in typeItems {
			typeItem.cloudKitRecord = nil
		}
	}

	func reIndex(completion: (()->Void)? = nil) {
		Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: [uuid.uuidString], acknowledgementHandler: completion ?? {})
	}

	var shareOwnerName: String? {
		guard let p = cloudKitShareRecord?.owner.userIdentity.nameComponents else { return nil }
		let f = PersonNameComponentsFormatter()
		return f.string(from: p)
	}

	func delete() {
		isDeleting = true
		if isImportedShare, let share = cloudKitShareRecord {
			CloudManager.markAsDeleted(recordName: share.recordID.recordName, cloudKitRecord: share)
		} else if cloudKitRecord != nil {
			CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
		} else {
			log("No cloud record for this item, skipping cloud delete")
		}
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uuid.uuidString]) { error in
			if let error = error {
				log("Error while deleting an index \(error)")
			}
		}
		removeIntents()
		clearCacheData(for: uuid)
		for item in typeItems {
			clearCacheData(for: item.uuid)
		}
		dataAccessQueue.sync {
			let f = FileManager.default
			if f.fileExists(atPath: folderUrl.path) {
				try? f.removeItem(at: folderUrl)
			}
		}
        #if MAINAPP
        MirrorManager.removeItems(items: [self])
        #endif
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

	var mostRelevantTypeItem: ArchivedDropItemType? {
		return typeItems.max { $0.contentPriority < $1.contentPriority }
	}

	var itemProviderForSharing: NSItemProvider {
		let p = NSItemProvider()
		typeItems.forEach { $0.registerForSharing(with: p) }
		return p
	}

	var loadingError: (String, Error)? {
		for item in typeItems {
			if let e = item.loadingError {
				return ("Error processing type \(item.typeIdentifier): ", e)
			}
		}
		return nil
	}

	var previewableTypeItem: ArchivedDropItemType? {
		return typeItems.sorted { $0.contentPriority > $1.contentPriority }.first { $0.canPreview }
	}

	static func updateUserActivity(_ activity: NSUserActivity, from item: ArchivedDropItem, child: ArchivedDropItemType?, titled: String) {
		let uuidString = item.uuid.uuidString
		activity.title = titled + " \"" + item.trimmedName + "\""

		var userInfo = [kGladysDetailViewingActivityItemUuid: uuidString]
		userInfo[kGladysDetailViewingActivityItemTypeUuid] = child?.uuid.uuidString
		activity.userInfo = userInfo

		activity.isEligibleForHandoff = true
		activity.isEligibleForPublicIndexing = false

		#if MAC
			activity.isEligibleForSearch = false
		#else
        activity.isEligibleForPrediction = true
        activity.contentAttributeSet = item.searchAttributes
        activity.contentAttributeSet?.relatedUniqueIdentifier = uuidString
        activity.isEligibleForSearch = true
		#endif
	}
}
