import CloudKit

final actor PushState {
    var latestError: Error?

    private var dataItemsToPush: Int
    private var dropsToPush: Int

    private let database: CKDatabase
    private let uuid2progress = [String: Progress]()
    private let recordsToDelete: [[CKRecord.ID]]
    private let payloadsToPush: [[CKRecord]]
    private let currentUUIDSequence: [String]

    init(zoneId: CKRecordZone.ID, database: CKDatabase) async {
        self.database = database

        let drops = await Model.allDrops

        var idsToPush = [String]()

        var _dropsToPush = 0
        var _dataItemsToPush = 0
        var _uuid2progress = [String: Progress]()
        var _payloadsToPush = drops.compactMap { item -> [CKRecord]? in
            guard let itemRecord = item.populatedCloudKitRecord else { return nil }
            if itemRecord.recordID.zoneID != zoneId {
                return nil
            }
            _dataItemsToPush += item.components.count
            _dropsToPush += 1
            var payload = item.components.compactMap(\.populatedCloudKitRecord)
            payload.append(itemRecord)

            let itemId = item.uuid.uuidString
            idsToPush.append(itemId)
            idsToPush.append(contentsOf: item.components.map(\.uuid.uuidString))
            _uuid2progress[itemId] = Progress(totalUnitCount: 100)
            item.components.forEach { _uuid2progress[$0.uuid.uuidString] = Progress(totalUnitCount: 100) }

            return payload
        }.flatBunch(minSize: 10)

        var newQueue = await CloudManager.deletionQueue
        if !idsToPush.isEmpty {
            let previousCount = newQueue.count
            newQueue = newQueue.filter { !idsToPush.contains($0) }
            if newQueue.count != previousCount {
                await CloudManager.setDeletionQueueAsync(newQueue)
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
            currentUUIDSequence = drops.map(\.uuid.uuidString)
            if await PushState.sequenceNeedsUpload(currentUUIDSequence) {
                var sequenceToSend: [String]?

                if await CloudManager.lastSyncCompletion == .distantPast {
                    if !currentUUIDSequence.isEmpty {
                        var mergedSequence = await CloudManager.uuidSequence
                        let mergedSet = Set(mergedSequence)
                        for i in currentUUIDSequence.reversed() where !mergedSet.contains(i) {
                            mergedSequence.insert(i, at: 0)
                        }
                        sequenceToSend = mergedSequence
                    }
                } else {
                    sequenceToSend = currentUUIDSequence
                }

                if let sequenceToSend {
                    let recordType = CloudManager.RecordType.positionList.rawValue
                    let record = await CloudManager.uuidSequenceRecord ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordType, zoneID: zoneId))
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

    private static func sequenceNeedsUpload(_ currentSequence: [String]) async -> Bool {
        var previousSequence = await CloudManager.uuidSequence

        let currentSet = Set(currentSequence)
        if currentSet.subtracting(previousSequence).count > 0 {
            // we have a new item
            return true
        }
        previousSequence = previousSequence.filter { currentSet.contains($0) }
        return currentSequence != previousSequence
    }

    func updateSyncMessage() {
        var components = [String]()
        if dropsToPush > 0 { components.append(dropsToPush == 1 ? "1 Drop" : "\(dropsToPush) Drops") }
        if dataItemsToPush > 0 { components.append(dataItemsToPush == 1 ? "1 Component" : "\(dataItemsToPush) Components") }
        let deletionCount = recordsToDelete.count
        if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
        let cs = components
        Task { @MainActor in
            CloudManager.setSyncProgressString("Sending" + (cs.isEmpty ? "" : (" " + cs.joined(separator: ", "))))
        }
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

    private func handleDeletion(deletedRecordIds: [CKRecord.ID]?, recordIdList: [CKRecord.ID], error: Error?) async {
        let requestedDeletionUUIDs = recordIdList.map(\.recordName)
        let deletedUUIDs = deletedRecordIds?.map(\.recordName) ?? []
        for uuid in requestedDeletionUUIDs {
            if deletedUUIDs.contains(uuid) {
                log("Confirmed deletion of item (\(uuid))")
            } else {
                log("Didn't need to delete item (\(uuid))")
            }
        }

        if let error {
            latestError = error
            log("Error deleting items: \(error.finalDescription)")
            await CloudManager.commitDeletion(for: deletedUUIDs) // play it safe
        } else {
            await CloudManager.commitDeletion(for: requestedDeletionUUIDs)
        }
        updateSyncMessage()
    }

    private var deletionOperations: [CKDatabaseOperation] {
        recordsToDelete.map { recordIdList in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIdList)
            operation.database = database
            operation.savePolicy = .allKeys
            operation.modifyRecordsCompletionBlock = { _, deletedRecordIds, error in
                Task {
                    await self.handleDeletion(deletedRecordIds: deletedRecordIds, recordIdList: recordIdList, error: error)
                }
            }
            return operation
        }
    }

    private func recordsModified(updatedRecords: [CKRecord]?, error: Error?) async {
        if let error {
            log("Error updating cloud records: \(error.finalDescription)")
            latestError = error
        }
        for record in updatedRecords ?? [] {
            let itemUUID = record.recordID.recordName
            if itemUUID == CloudManager.RecordType.positionList.rawValue {
                await CloudManager.setUuidSequenceAsync(currentUUIDSequence)
                await CloudManager.setUuidSequenceRecordAsync(record)
            } else if let item = await Model.item(uuid: itemUUID) {
                item.cloudKitRecord = record
                dropsToPush -= 1
            } else if let typeItem = await Model.component(uuid: itemUUID) {
                typeItem.cloudKitRecord = record
                dataItemsToPush -= 1
            }
            log("Sent updated \(record.recordType) cloud record (\(itemUUID))")
        }
        updateSyncMessage()
    }

    private func progress(record: CKRecord, progress: Double) {
        let recordProgress = uuid2progress[record.recordID.recordName]
        recordProgress?.completedUnitCount = Int64(progress * 100.0)
    }

    private var pushOperations: [CKDatabaseOperation] {
        payloadsToPush.map { recordList in
            let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
            operation.database = database
            operation.savePolicy = .allKeys
            operation.perRecordProgressBlock = { record, progress in
                Task {
                    self.progress(record: record, progress: progress)
                }
            }
            operation.modifyRecordsCompletionBlock = { updatedRecords, _, error in
                Task {
                    await self.recordsModified(updatedRecords: updatedRecords, error: error)
                }
            }
            return operation
        }
    }

    var operations: [CKDatabaseOperation] {
        deletionOperations + pushOperations
    }
}
