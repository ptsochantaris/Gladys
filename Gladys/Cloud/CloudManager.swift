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

	static var syncProgressString: String? {
		didSet {
			#if DEBUG
			if let s = syncProgressString {
				log(">>> Sync update: \(s)")
			} else {
				log(">>> Sync updates done")
			}
			#endif
			NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
		}
	}

	/////////////////////////////////////////////

	private static func sequenceNeedsUpload(_ currentSequence: [String]) -> Bool {
		var previousSequence = uuidSequence
		for localItem in currentSequence {
			if !previousSequence.contains(localItem) { // we have a new item
				return true
			}
		}
		previousSequence = previousSequence.filter { currentSequence.contains($0) }
		return currentSequence != previousSequence
	}

	@discardableResult
	static func sendUpdatesUp(completion: @escaping (Error?)->Void) -> Progress? {
		if !syncSwitchedOn {
			CloudManager.shareActionIsActioningIds = []
			completion(nil)
			return nil
		}

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

		var idsToPush = [String]()
		var dataItemsToPush = 0
		var dropsToPush = 0
		var uuid2progress = [String: Progress]()

		let drops = Model.drops
		var payloadsToPush = drops.compactMap { item -> [CKRecord]? in
			if let itemRecord = item.populatedCloudKitRecord {
				dataItemsToPush += item.typeItems.count
				dropsToPush += 1
				var payload = item.typeItems.compactMap { $0.populatedCloudKitRecord }
				payload.append(itemRecord)

				let itemId = item.uuid.uuidString
				idsToPush.append(itemId)
				uuid2progress[itemId] = Progress(totalUnitCount: 100)
				item.typeItems.forEach { uuid2progress[$0.uuid.uuidString] = Progress(totalUnitCount: 100) }

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

		let currentUUIDSequence = drops.map { $0.uuid.uuidString }
		if sequenceNeedsUpload(currentUUIDSequence) {

			var sequenceToSend: [String]?

			if lastSyncCompletion == .distantPast {
				if currentUUIDSequence.count > 0 {
					var mergedSequence = uuidSequence
					for i in currentUUIDSequence.reversed() {
						if !mergedSequence.contains(i) {
							mergedSequence.insert(i, at: 0)
						}
					}
					sequenceToSend = mergedSequence
				}
			} else {
				sequenceToSend = currentUUIDSequence
			}

			if let sequenceToSend = sequenceToSend {
				let record = uuidSequenceRecord ?? CKRecord(recordType: "PositionList", recordID: CKRecordID(recordName: "PositionList", zoneID: zoneId))
				record["positionList"] = sequenceToSend as NSArray
				if payloadsToPush.count > 0 {
					payloadsToPush[0].insert(record, at: 0)
				} else {
					payloadsToPush.append([record])
				}
			}
		}

		let recordsToDelete = deletionIdsSnapshot.map { CKRecordID(recordName: $0, zoneID: zoneId) }.bunch(maxSize: 100)

		if payloadsToPush.count == 0 && recordsToDelete.count == 0 {
			log("No further changes to push up")
			#if MAINAPP
				CloudManager.shareActionIsActioningIds = []
			#endif
			completion(nil)
			return nil
		}

		let progress = Progress(totalUnitCount: Int64(dropsToPush + dataItemsToPush) * 100)
		for (k, v) in uuid2progress {
			progress.addChild(v, withPendingUnitCount: 100)
		}
		syncProgressString = "Sending changes"

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
						log("Error deleting items: \(error.finalDescription)")
					}
					for uuid in (deletedRecordIds?.map({ $0.recordName })) ?? [] {
						if deletionIdsSnapshot.contains(uuid) {
							deletionQueue.remove(uuid)
							log("Deleted cloud record \(uuid)")
						}
					}
					updateSyncMessage()
				}
			}
			operations.append(operation)
		}

		log("Pushing up \(payloadsToPush.count) item blocks")

		func updateSyncMessage() {
			var components = [String]()
			if dropsToPush > 0 { components.append(dropsToPush == 1 ? "1 Drop" : "\(dropsToPush) Drops") }
			if dataItemsToPush > 0 { components.append(dataItemsToPush == 1 ? "1 Component" : "\(dataItemsToPush) Components") }
			let deletionCount = deletionQueue.count
			if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
			syncProgressString = "Sending" + (components.count > 0 ? (" " + components.joined(separator: ", ")) : "")
		}

		updateSyncMessage()

		for recordList in payloadsToPush {
			let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
			operation.savePolicy = .allKeys
			operation.isAtomic = true
			operation.perRecordProgressBlock = { record, progress in
				DispatchQueue.main.async {
					let recordProgress = uuid2progress[record.recordID.recordName]
					recordProgress?.completedUnitCount = Int64(progress * 100.0)
				}
			}
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error updating cloud records: \(error.finalDescription)")
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
							dropsToPush -= 1
						} else if let typeItem = Model.typeItem(uuid: itemUUID) {
							typeItem.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
							dataItemsToPush -= 1
						}
					}
					updateSyncMessage()
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
			#if MAINAPP
				CloudManager.shareActionIsActioningIds = []
			#endif
			completion(latestError)
		}
		operations.forEach {
			go($0)
		}

		return progress
	}
}
