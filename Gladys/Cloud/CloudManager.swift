//
//  CloudManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 21/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CloudKit

final class CloudManager {

	static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

	static func go(_ operation: CKDatabaseOperation) {
		operation.qualityOfService = .userInitiated
		container.privateCloudDatabase.add(operation)
	}

	static var syncDirty = false

	/////////////////////////////////////////////

	static func sendUpdatesUp(completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { completion(nil); return }

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

		var idsToPush = [String]()
		var payloadsToPush = Model.drops.flatMap { item -> [CKRecord]? in
			if let itemRecord = item.populatedCloudKitRecord {
				var payload = item.typeItems.flatMap { $0.populatedCloudKitRecord }
				payload.append(itemRecord)
				idsToPush.append(item.uuid.uuidString)
				return payload
			}
			return nil
		}.flatBunch(minSize: 10)

		var deletionIdsSnapshot = deletionQueue
		if idsToPush.count > 0 {
			let previousCount = deletionIdsSnapshot.count
			deletionIdsSnapshot = deletionIdsSnapshot.filter { !idsToPush.contains($0) }
			if deletionIdsSnapshot.count != previousCount {
				deletionQueue = deletionIdsSnapshot
			}
		}

		let currentUUIDSequence = Model.drops.map { $0.uuid.uuidString }
		if lastSyncCompletion != .distantPast && uuidSequence != currentUUIDSequence { // only send position record if we've synced before and things have moved around
			let record = uuidSequenceRecord ?? CKRecord(recordType: "PositionList", recordID: CKRecordID(recordName: "PositionList", zoneID: zoneId))
			record["positionList"] = currentUUIDSequence as NSArray
			payloadsToPush.append([record])
		}

		let recordsToDelete = deletionIdsSnapshot.map { CKRecordID(recordName: $0, zoneID: zoneId) }.bunch(maxSize: 100)

		if payloadsToPush.count == 0 && recordsToDelete.count == 0 {
			log("No further changes to push up")
			completion(nil)
			return
		}

		var latestError: Error?
		var operations = [CKDatabaseOperation]()

		log("Pushing up \(recordsToDelete.count) item deletion blocks")

		for recordIdList in recordsToDelete {
			let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIdList)
			operation.savePolicy = .allKeys
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						latestError = error
						log("Error deleting items: \(error.localizedDescription)")
					}
					for uuid in (deletedRecordIds?.map({ $0.recordName })) ?? [] {
						if deletionIdsSnapshot.contains(uuid) {
							deletionQueue.remove(uuid)
							log("Deleted cloud record \(uuid)")
						}
					}
				}
			}
			operations.append(operation)
		}

		log("Pushing up \(payloadsToPush.count) item blocks")

		for recordList in payloadsToPush {
			let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
			operation.savePolicy = .allKeys
			operation.isAtomic = true
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error updating cloud records: \(error.localizedDescription)")
						latestError = error
					}
					for record in updatedRecords ?? [] {
						let itemUUID = record.recordID.recordName
						if itemUUID == "PositionList" {
							uuidSequence = currentUUIDSequence
							uuidSequenceRecord = record
							log("Sent updated \(record.recordType) cloud record")
						} else if let item = Model.item(uuid: itemUUID) {
							item.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
						} else if let typeItem = Model.typeItem(uuid: itemUUID) {
							typeItem.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
						}
					}
				}
			}
			operations.append(operation)
		}

		let group = DispatchGroup()
		operations.forEach {
			group.enter()
			$0.completionBlock = {
				group.leave()
			}
		}
		group.notify(queue: DispatchQueue.main) {
			completion(latestError)
		}
		operations.forEach {
			go($0)
		}
	}
}
