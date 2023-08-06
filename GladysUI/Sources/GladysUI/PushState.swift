import CloudKit
import GladysCommon
import Lista

final actor PushState {
    var latestError: Error?

    private var dataItemsToPush: Int
    private var dropsToPush: Int

    private let database: CKDatabase
    private let recordsToDelete: [[CKRecord.ID]]
    private let payloadsToPush: [[CKRecord]]
    private let currentUUIDSequence: [String]

    init(zoneId: CKRecordZone.ID, database: CKDatabase) async {
        self.database = database

        let drops = await DropStore.allDrops

        var idsToPush = Set<String>()

        var _dropsToPush = 0
        var _dataItemsToPush = 0
        var _payloadsToPush = drops.compactMap { item -> [CKRecord]? in
            guard let itemRecord = item.populatedCloudKitRecord,
                  itemRecord.recordID.zoneID == zoneId
            else {
                return nil
            }
            _dataItemsToPush += item.components.count
            _dropsToPush += 1

            let itemId = item.uuid.uuidString
            idsToPush.insert(itemId)
            idsToPush.formUnion(item.components.map(\.uuid.uuidString))

            var payload = item.components.compactMap(\.populatedCloudKitRecord)
            payload.append(itemRecord)
            return payload.uniqued

        }.flatBunch(minSize: 20)

        let newDeletionQueue = await CloudManager.deletionQueue
        if !idsToPush.isEmpty, !newDeletionQueue.isEmpty {
            let previousCount = newDeletionQueue.count
            let filteredDeletionQueue = newDeletionQueue.filter { !idsToPush.contains($0) }
            if filteredDeletionQueue.count != previousCount {
                Task { @CloudActor in
                    CloudManager.deletionQueue = filteredDeletionQueue
                }
            }
        }
        recordsToDelete = newDeletionQueue.compactMap {
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
        }.uniqued.bunch(maxSize: 100)

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
        let components = Lista<String>()
        if dropsToPush > 0 { components.append(dropsToPush == 1 ? "1 Drop" : "\(dropsToPush) Drops") }
        if dataItemsToPush > 0 { components.append(dataItemsToPush == 1 ? "1 Component" : "\(dataItemsToPush) Components") }
        let deletionCount = recordsToDelete.count
        if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
        Task {
            await CloudManager.setSyncProgressString("Sending" + (components.count == 0 ? "" : (" " + components.joined(separator: ", "))))
        }
    }

    private var deletionOperations: [CKDatabaseOperation] {
        recordsToDelete.map { recordIdList in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIdList)
            operation.database = database
            operation.savePolicy = .allKeys
            var deletedRecordIds = [String]()
            operation.perRecordDeleteBlock = { id, result in
                let uuid = id.recordName
                switch result {
                case .success:
                    deletedRecordIds.append(uuid)
                    log("Confirmed cloud deletion of item (\(uuid))")
                case let .failure(error):
                    if error.itemDoesNotExistOnServer {
                        log("Didn't need to cloud delete item (\(uuid))")
                    } else {
                        log("Error in cloud deletion of item (\(uuid)): \(error.localizedDescription)")
                    }
                }
            }
            operation.modifyRecordsResultBlock = { result in
                Task {
                    switch result {
                    case .success:
                        log("Item cloud deletions completed")
                        await CloudManager.commitDeletion(for: deletedRecordIds)
                    case let .failure(error):
                        self.latestError = error
                        log("Error in cloud deletion of items: \(error.localizedDescription)")
                    }
                    self.updateSyncMessage()
                }
            }
            return operation
        }
    }

    private var pushOperations: [CKDatabaseOperation] {
        payloadsToPush.map { recordList in
            let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
            operation.database = database
            operation.savePolicy = .allKeys

            let updatedRecords = Lista<CKRecord>()

            operation.perRecordSaveBlock = { id, result in
                switch result {
                case let .success(record):
                    updatedRecords.append(record)
                    log("Confirmed cloud save of item \(record.recordType) id (\(id.recordName))")
                case let .failure(error):
                    log("Error in cloud save of item (\(id.recordName)): \(error.localizedDescription)")
                }
            }

            operation.modifyRecordsResultBlock = { result in
                Task {
                    switch result {
                    case .success:
                        for record in updatedRecords {
                            let itemUUID = record.recordID.recordName
                            if itemUUID == CloudManager.RecordType.positionList.rawValue {
                                Task { @CloudActor in
                                    CloudManager.uuidSequence = self.currentUUIDSequence
                                    CloudManager.uuidSequenceRecord = record
                                }
                            } else if let item = await DropStore.item(uuid: itemUUID) {
                                item.cloudKitRecord = record
                                self.dropsToPush -= 1
                            } else if let typeItem = ComponentLookup.shared.component(uuid: itemUUID) {
                                typeItem.cloudKitRecord = record
                                self.dataItemsToPush -= 1
                            }
                        }

                    case let .failure(error):
                        log("Error updating cloud records: \(error.localizedDescription)")
                        self.latestError = error
                    }
                    self.updateSyncMessage()
                }
            }

            return operation
        }
    }

    var operations: [CKDatabaseOperation] {
        deletionOperations + pushOperations
    }
}
