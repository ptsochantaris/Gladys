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

	var shareOwnerName: String? {
		guard let p = cloudKitShareRecord?.owner.userIdentity.nameComponents else { return nil }
		let f = PersonNameComponentsFormatter()
		return f.string(from: p)
	}

	func delete() {

        if shouldDisplayLoading {
            cancelIngest()
        }

        needsDeletion = true
		if isImportedShare, let share = cloudKitShareRecord {
			CloudManager.markAsDeleted(recordName: share.recordID.recordName, cloudKitRecord: share)
		} else if cloudKitRecord != nil {
			CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
		} else {
			log("No cloud record for this item, skipping cloud delete")
		}
		removeIntents()
        let p = folderUrl.path
		dataAccessQueue.async {
			let f = FileManager.default
			if f.fileExists(atPath: p) {
                try? f.removeItem(atPath: p)
			}
		}
        clearCacheData(for: uuid) // this must be last since we use URLs above
        for item in typeItems {
            clearCacheData(for: item.uuid)
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

	var mostRelevantTypeItem: ArchivedDropItemType? {
		return typeItems.max { $0.contentPriority < $1.contentPriority }
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
