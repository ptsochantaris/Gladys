import CloudKit

final class PushState {

	var latestError: Error?

	private var dataItemsToPush: Int
	private var dropsToPush: Int

	private let database: CKDatabase
	private let uuid2progress = [String: Progress]()
	private let recordsToDelete: [[CKRecordID]]
	private let payloadsToPush: [[CKRecord]]
	private let currentUUIDSequence: [String]
	private let deletionIdsSnapshot: Set<String>

	init(zoneId: CKRecordZoneID, database: CKDatabase) {
		self.database = database

		let drops = Model.drops

		var idsToPush = [String]()

		var _dropsToPush = 0
		var _dataItemsToPush = 0
		var _uuid2progress = [String: Progress]()
		var _payloadsToPush = drops.compactMap { item -> [CKRecord]? in
			guard let itemRecord = item.populatedCloudKitRecord else { return nil }
			if itemRecord.recordID.zoneID != zoneId {
				return nil
			}
			_dataItemsToPush += item.typeItems.count
			_dropsToPush += 1
			var payload = item.typeItems.compactMap { $0.populatedCloudKitRecord }
			payload.append(itemRecord)

			let itemId = item.uuid.uuidString
			idsToPush.append(itemId)
			idsToPush.append(contentsOf: item.typeItems.map { $0.uuid.uuidString } )
			_uuid2progress[itemId] = Progress(totalUnitCount: 100)
			item.typeItems.forEach { _uuid2progress[$0.uuid.uuidString] = Progress(totalUnitCount: 100) }

			return payload
		}.flatBunch(minSize: 10)

		var newQueue = CloudManager.deletionQueue
		if idsToPush.count > 0 {
			let previousCount = newQueue.count
			newQueue = newQueue.filter { !idsToPush.contains($0) }
			if newQueue.count != previousCount {
				CloudManager.deletionQueue = newQueue
			}
		}
		var newSnapShot = Set<String>()
		recordsToDelete = newQueue.compactMap {
			let components = $0.components(separatedBy: ":")
			if components.count > 2 {
				if zoneId.zoneName == components[0], zoneId.ownerName == components[1] {
					newSnapShot.insert(components[2])
					return CKRecordID(recordName: components[2], zoneID: zoneId)
				} else {
					return nil
				}
			} else if zoneId == privateZoneId {
				newSnapShot.insert(components[0])
				return CKRecordID(recordName: components[0], zoneID: zoneId)
			} else {
				return nil
			}
		}.bunch(maxSize: 100)
		deletionIdsSnapshot = newSnapShot

		if zoneId == privateZoneId {
			currentUUIDSequence = drops.map { $0.uuid.uuidString }
			if PushState.sequenceNeedsUpload(currentUUIDSequence) {

				var sequenceToSend: [String]?

				if CloudManager.lastSyncCompletion == .distantPast {
					if currentUUIDSequence.count > 0 {
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
					let record = CloudManager.uuidSequenceRecord ?? CKRecord(recordType: CloudManager.RecordType.positionList, recordID: CKRecordID(recordName: CloudManager.RecordType.positionList, zoneID: zoneId))
					record["positionList"] = sequenceToSend as NSArray
					if _payloadsToPush.count > 0 {
						_payloadsToPush[0].insert(record, at: 0)
					} else {
						_payloadsToPush.append([record])
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
		CloudManager.syncProgressString = "Sending" + (components.count > 0 ? (" " + components.joined(separator: ", ")) : "")
	}

	var progress: Progress {
		let progress = Progress(totalUnitCount: Int64(dropsToPush + dataItemsToPush) * 100)
		for v in uuid2progress.values {
			progress.addChild(v, withPendingUnitCount: 100)
		}
		log("Pushing up \(recordsToDelete.count) item deletion blocks, \(payloadsToPush.count) item blocks")
		updateSyncMessage()
		return progress
	}

	var deletionOperations: [CKDatabaseOperation] {
		return recordsToDelete.map { recordIdList in
			let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIdList)
			operation.database = database
			operation.savePolicy = .allKeys
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						self.latestError = error
						log("Error deleting items: \(error.finalDescription)")
					}
					for uuid in (deletedRecordIds?.map({ $0.recordName })) ?? [] {
						if self.deletionIdsSnapshot.contains(uuid) {
							CloudManager.deletionQueue.remove(uuid)
							log("Deleted cloud record \(uuid)")
						}
					}
					self.updateSyncMessage()
				}
			}
			return operation
		}
	}

	var pushOperations: [CKDatabaseOperation] {
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
						if itemUUID == CloudManager.RecordType.positionList {
							CloudManager.uuidSequence = self.currentUUIDSequence
							CloudManager.uuidSequenceRecord = record
						} else if let item = Model.item(uuid: itemUUID) {
							item.cloudKitRecord = record
							self.dropsToPush -= 1
						} else if let typeItem = Model.typeItem(uuid: itemUUID) {
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
