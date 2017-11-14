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
		cloudKitRecord = record
		needsReIngest = true
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
			CKRecord(recordType: "ArchivedDropItem",
			         recordID: CKRecordID(recordName: uuid.uuidString,
			                              zoneID: CKRecordZoneID(zoneName: "archivedDropItems",
			                                                     ownerName: CKCurrentUserDefaultName)))

		record["suggestedName"] = suggestedName as NSString?
		record["createdAt"] = createdAt as NSDate
		record["updatedAt"] = updatedAt as NSDate
		record["note"] = note as NSString
		record["titleOverride"] = titleOverride as NSString
		if labels.isEmpty {
			record["labels"] = nil
		} else {
			record["labels"] = labels as NSArray
		}
		return record
	}
}
