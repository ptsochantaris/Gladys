//
//  ArchivedItem+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CoreSpotlight

extension ArchivedItem {

	private static let dateFormatter: DateFormatter = {
		let d = DateFormatter()
		d.doesRelativeDateFormatting = true
		d.dateStyle = .short
		d.timeStyle = .short
		return d
	}()

	var shouldDisplayLoading: Bool {
        return flags.contains(.isBeingCreatedBySync) || needsReIngest || loadingProgress != nil
	}

	func removeFromCloudkit() {
		cloudKitRecord = nil
		cloudKitShareRecord = nil
		for typeItem in components {
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
        for item in components {
            clearCacheData(for: item.uuid)
        }
	}

	func renumberTypeItems() {
		var count = 0
		for i in components {
			i.order = count
			count += 1
		}
	}

	func postModified() {
		NotificationCenter.default.post(name: .ItemModified, object: self)
	}

	var addedString: String {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes) + "\n" + ArchivedItem.dateFormatter.string(from: createdAt)
	}

	var mostRelevantTypeItem: Component? {
		return components.max { $0.contentPriority < $1.contentPriority }
	}

	var previewableTypeItem: Component? {
        return components.filter { $0.canPreview }.max { $0.contentPriority < $1.contentPriority }
	}

	static func updateUserActivity(_ activity: NSUserActivity, from item: ArchivedItem, child: Component?, titled: String) {
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
