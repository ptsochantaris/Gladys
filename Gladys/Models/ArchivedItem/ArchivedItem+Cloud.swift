//
//  ArchivedItem+Cloud.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit

extension ArchivedItem {
	func cloudKitUpdate(from record: CKRecord) {

		updatedAt = record["updatedAt"] as? Date ?? .distantPast
		titleOverride = record["titleOverride"] as? String ?? ""
		note = record["note"] as? String ?? ""

		lockPassword = record["lockPassword"] as? Data
		lockHint = record["lockHint"] as? String
		labels = (record["labels"] as? [String]) ?? []

		needsReIngest = true
        if isLocked {
            flags.insert(.needsUnlock)
        } else {
            flags.remove(.needsUnlock)
        }

		cloudKitRecord = record
	}

	var parentZone: CKRecordZone.ID {
		return cloudKitRecord?.recordID.zoneID ?? privateZoneId
	}

	func sharedInZone(zoneId: CKRecordZone.ID) -> Bool {
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
			         recordID: CKRecord.ID(recordName: uuid.uuidString, zoneID: privateZoneId))

        record.setValuesForKeys([
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "note": note,
            "titleOverride": titleOverride,
        ])
        
        record["labels"] = labels.isEmpty ? nil : labels
		record["suggestedName"] = suggestedName
        record["lockPassword"] = lockPassword
        record["lockHint"] = lockHint
		return record
	}
}
