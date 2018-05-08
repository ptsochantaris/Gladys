//
//  ArchivedDropItemType+Cloud.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit

extension ArchivedDropItemType {

	func cloudKitUpdate(from record: CKRecord) {
		updatedAt = record["updatedAt"] as! Date
		typeIdentifier = record["typeIdentifier"] as! String
		representedClass = record["representedClass"] as! String
		classWasWrapped = (record["classWasWrapped"] as! Int != 0)
		accessoryTitle = record["accessoryTitle"] as? String
		order = record["order"] as? Int ?? 0
		if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
			let path = bytesPath
			let f = FileManager.default
			if f.fileExists(atPath: path.path) {
				try? f.removeItem(at: path)
			}
			try? f.copyItem(at: assetURL, to: path)
		}
		cloudKitRecord = record
	}

	var populatedCloudKitRecord: CKRecord? {

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems",
		                            ownerName: CKCurrentUserDefaultName)

		let record = cloudKitRecord ?? CKRecord(recordType: "ArchivedDropItemType",
		                                        recordID: CKRecordID(recordName: uuid.uuidString,
		                                                             zoneID: zoneId))

		let parentId = CKRecordID(recordName: parentUuid.uuidString, zoneID: zoneId)
		record["parent"] = CKReference(recordID: parentId, action: CKReferenceAction.deleteSelf)

		if bytes != nil {
			record["bytes"] = CKAsset(fileURL: bytesPath)
		}

		record["createdAt"] = createdAt as NSDate
		record["updatedAt"] = updatedAt as NSDate
		record["typeIdentifier"] = typeIdentifier as NSString
		record["representedClass"] = representedClass as NSString
		record["classWasWrapped"] = NSNumber(value: classWasWrapped ? 1 : 0)
		record["accessoryTitle"] = accessoryTitle as NSString?
		record["order"] = order as NSNumber

		return record
	}

}
