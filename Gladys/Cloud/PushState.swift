import CloudKit

final class PushState {

	var latestError: Error?

	private var dataItemsToPush: Int
	private var dropsToPush: Int

	private let database: CKDatabase
	private let uuid2progress = [String: Progress]()
	private let recordsToDelete: [[CKRecord.ID]]
	private let payloadsToPush: [[CKRecord]]
	private let currentUUIDSequence: [String]

	init(zoneId: CKRecordZone.ID, database: CKDatabase) {
		self.database = database

		let drops = Model.drops

		var idsToPush = [String]()

		var _dropsToPush = 0
		var _dataItemsToPush = 0
		var _uuid2progress = [String: Progress]()
		var _payloadsToPush = drops.all.compactMap { item -> [CKRecord]? in
			guard let itemRecord = item.populatedCloudKitRecord else { return nil }
			if itemRecord.recordID.zoneID != zoneId {
				return nil
			}
			_dataItemsToPush += item.components.count
			_dropsToPush += 1
			var payload = item.components.compactMap { $0.populatedCloudKitRecord }
			payload.append(itemRecord)

			let itemId = item.uuid.uuidString
			idsToPush.append(itemId)
			idsToPush.append(contentsOf: item.components.map { $0.uuid.uuidString })
			_uuid2progress[itemId] = Progress(totalUnitCount: 100)
			item.components.forEach { _uuid2progress[$0.uuid.uuidString] = Progress(totalUnitCount: 100) }

			return payload
		}.flatBunch(minSize: 10)

		var newQueue = CloudManager.deletionQueue
		if !idsToPush.isEmpty {
			let previousCount = newQueue.count
			newQueue = newQueue.filter { !idsToPush.contains($0) }
			if newQueue.count != previousCount {
				CloudManager.deletionQueue = newQueue
			}
		}
		recordsToDelete = newQueue.compactMap {
			let components = $0.components(separatedBy: ":")
			if components.count > 2 {
				if zoneId.zoneName == components[0], zoneId.ownerName == components[1] {
					return CKRecord.ID(recordName: components[2], zoneID: zoneId)
				} else {
					return nil
				}
			} else if zoneId == privateZoneId {
				return CKRecord.ID(recordName: components[0], zoneID: zoneId)
			} else {
				return nil
			}
		}.bunch(maxSize: 100)

		if zoneId == privateZoneId {
			currentUUIDSequence = drops.all.map { $0.uuid.uuidString }
			if PushState.sequenceNeedsUpload(currentUUIDSequence) {

				var sequenceToSend: [String]?

				if CloudManager.lastSyncCompletion == .distantPast {
					if !currentUUIDSequence.isEmpty {
						var mergedSequence = CloudManager.uuidSequence
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
                    let recordType = CloudManager.RecordType.positionList.rawValue
					let record = CloudManager.uuidSequenceRecord ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordType, zoneID: zoneId))
					record["positionList"] = sequenceToSend as NSArray
					if _payloadsToPush.isEmpty {
                        _payloadsToPush.append([record])
					} else {
                        _payloadsToPush[0].insert(record, at: 0)
					}
				}
			}
		} else {
			currentUUIDSequence = []
		}

		dataItemsToPush = _dataItemsToPush
		dropsToPush = _dropsToPush
		payloadsToPush = _payloadsToPush
	}

	static private func sequenceNeedsUpload(_ currentSequence: [String]) -> Bool {
		var previousSequence = CloudManager.uuidSequence
		for localItem in currentSequence {
			if !previousSequence.contains(localItem) { // we have a new item
				return true
			}
		}
		previousSequence = previousSequence.filter { currentSequence.contains($0) }
		return currentSequence != previousSequence
	}

	func updateSyncMessage() {
		var components = [String]()
		if dropsToPush > 0 { components.append(dropsToPush == 1 ? "1 Drop" : "\(dropsToPush) Drops") }
		if dataItemsToPush > 0 { components.append(dataItemsToPush == 1 ? "1 Component" : "\(dataItemsToPush) Components") }
		let deletionCount = recordsToDelete.count
		if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
        CloudManager.syncProgressString = "Sending" + (components.isEmpty ? "" : (" " + components.joined(separator: ", ")))
	}

	var progress: Progress {
		let progress = Progress(totalUnitCount: Int64(dropsToPush + dataItemsToPush) * 100)
		for v in uuid2progress.values {
			progress.addChild(v, withPendingUnitCount: 100)
		}
		let deleteCount = recordsToDelete.count
		let pushCount = payloadsToPush.count
		if deleteCount + pushCount > 0 {
			log("Pushing up \(deleteCount) item deletion blocks, \(pushCount) item blocks")
			updateSyncMessage()
		}
		return progress
	}

	private var deletionOperations: [CKDatabaseOperation] {
		return recordsToDelete.map { recordIdList in
			let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIdList)
			operation.database = database
			operation.savePolicy = .allKeys
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in

				let requestedDeletionUUIDs = recordIdList.map { $0.recordName }
				let deletedUUIDs = deletedRecordIds?.map { $0.recordName } ?? []
				for uuid in requestedDeletionUUIDs {
					if deletedUUIDs.contains(uuid) {
						log("Confirmed deletion of item (\(uuid))")
					} else {
						log("Didn't need to delete item (\(uuid))")
					}
				}

				DispatchQueue.main.async {
					if let error = error {
						self.latestError = error
						log("Error deleting items: \(error.finalDescription)")
						CloudManager.commitDeletion(for: deletedUUIDs) // play it safe
					} else {
						CloudManager.commitDeletion(for: requestedDeletionUUIDs)
					}
					self.updateSyncMessage()
				}
			}
			return operation
		}
	}

	private var pushOperations: [CKDatabaseOperation] {
		return payloadsToPush.map { recordList in
			let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
			operation.database = database
			operation.savePolicy = .allKeys
			operation.perRecordProgressBlock = { record, progress in
				DispatchQueue.main.async {
					let recordProgress = self.uuid2progress[record.recordID.recordName]
					recordProgress?.completedUnitCount = Int64(progress * 100.0)
				}
			}
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error updating cloud records: \(error.finalDescription)")
						self.latestError = error
					}
					for record in updatedRecords ?? [] {
						let itemUUID = record.recordID.recordName
                        if itemUUID == CloudManager.RecordType.positionList.rawValue {
							CloudManager.uuidSequence = self.currentUUIDSequence
							CloudManager.uuidSequenceRecord = record
						} else if let item = Model.item(uuid: itemUUID) {
							item.cloudKitRecord = record
							self.dropsToPush -= 1
						} else if let typeItem = Model.component(uuid: itemUUID) {
							typeItem.cloudKitRecord = record
							self.dataItemsToPush -= 1
						}
						log("Sent updated \(record.recordType) cloud record (\(itemUUID))")
					}
					self.updateSyncMessage()
				}
			}
			return operation
		}
	}

	var operations: [CKDatabaseOperation] {
		return deletionOperations + pushOperations
	}
}
