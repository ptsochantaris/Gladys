//
//  ArchivedDropItem+Cloud.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit

extension ArchivedDropItem {
	func cloudKitUpdate(from record: CKRecord) {
		updatedAt = record["updatedAt"] as! Date
		note = record["note"] as! String
		titleOverride = record["titleOverride"] as! String
		labels = (record["labels"] as? [String]) ?? []
		lockPassword = record["lockPassword"] as? Data
		lockHint = record["lockHint"] as? String
		cloudKitRecord = record
		needsUnlock = lockPassword != nil
		needsReIngest = true
	}

	var cloudKitSharingTitle: String {
		return displayTitleOrUuid.truncateWithEllipses(limit: 128)
	}

	var parentZone: CKRecordZoneID {
		return cloudKitRecord?.recordID.zoneID ?? privateZoneId
	}

	func sharedInZone(zoneId: CKRecordZoneID) -> Bool {
		return cloudKitRecord?.share?.recordID.zoneID == zoneId
	}

	var populatedCloudKitRecord: CKRecord? {

		#if MAINAPP
			if CloudManager.shareActionIsActioningIds.contains(uuid.uuidString) {
				log("Will not sync up item \(uuid.uuidString) since the action extension is taking care of it")
				return nil
			}
		#endif

		guard needsCloudPush && !needsDeletion && goodToSave else { return nil }

		let record = cloudKitRecord ??
			CKRecord(recordType: CloudManager.RecordType.item,
			         recordID: CKRecordID(recordName: uuid.uuidString, zoneID: privateZoneId))

		record["suggestedName"] = suggestedName as NSString?
		record["createdAt"] = createdAt as NSDate
		record["updatedAt"] = updatedAt as NSDate
		record["note"] = note as NSString
		record["titleOverride"] = titleOverride as NSString
		record["lockPassword"] = lockPassword as NSData?
		record["lockHint"] = lockHint as NSString?
		record["labels"] = labels.isEmpty ? nil : labels as NSArray
		return record
	}
}
