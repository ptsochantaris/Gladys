import CloudKit
import GladysCommon
import Lista

@SyncActor
final class PushState {
    private var componentsToPush: Int
    private var dropsToPush: Int

    private let database: CKDatabase
    private let recordIdsToDelete: [CKRecord.ID]
    private let recordsToUpload: [[CKRecord]]
    private let currentUUIDSequence: [String]

    init(zoneId: CKRecordZone.ID, database: CKDatabase) async {
        self.database = database

        let drops = await DropStore.allDrops

        var idsToPush = Set<String>()

        var _dropsToPush = 0
        var _dataItemsToPush = 0

        var _recordsToUpload = await drops.asyncCompactMap { @SyncActor item -> [CKRecord]? in
            guard let itemRecord = await item.populatedCloudKitRecord,
                  itemRecord.recordID.zoneID == zoneId
            else {
                return nil
            }
            let components = await item.components
            _dataItemsToPush += components.count
            _dropsToPush += 1

            let itemId = item.uuid.uuidString
            idsToPush.insert(itemId)
            await idsToPush.formUnion(components.asyncMap { @MainActor in $0.uuid.uuidString })

            var payload = await components.asyncMap { @MainActor in $0.populatedCloudKitRecord }
            payload.append(itemRecord)
            return payload.uniqued
        }.flatBunch(minSize: 100).uniqued

        let newDeletionQueue = await CloudManager.deletionQueue
        if idsToPush.isPopulated, newDeletionQueue.isPopulated {
            let previousCount = newDeletionQueue.count
            let filteredDeletionQueue = newDeletionQueue.filter { !idsToPush.contains($0) }
            if filteredDeletionQueue.count != previousCount {
                Task { @CloudActor in
                    CloudManager.deletionQueue = filteredDeletionQueue
                }
            }
        }
        recordIdsToDelete = newDeletionQueue.compactMap {
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
        }.uniqued

        if zoneId == privateZoneId {
            currentUUIDSequence = drops.map(\.uuid.uuidString)
            if await PushState.sequenceNeedsUpload(currentUUIDSequence) {
                var sequenceToSend: [String]?

                if await CloudManager.lastSyncCompletion == .distantPast {
                    if currentUUIDSequence.isPopulated {
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
                    if _recordsToUpload.isEmpty {
                        _recordsToUpload.append([record])
                    } else {
                        _recordsToUpload[0].insert(record, at: 0)
                    }
                }
            }
        } else {
            currentUUIDSequence = []
        }

        componentsToPush = _dataItemsToPush
        dropsToPush = _dropsToPush
        recordsToUpload = _recordsToUpload
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
        if componentsToPush > 0 { components.append(componentsToPush == 1 ? "1 Component" : "\(componentsToPush) Components") }
        let deletionCount = recordIdsToDelete.count
        if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
        Task { @CloudActor in
            CloudManager.setSyncProgressString("Sending" + (components.count == 0 ? "" : (" " + components.joined(separator: ", "))))
        }
    }

    func perform() async throws {
        do {
            for recordList in recordsToUpload {
                let outcome = try await database.modifyRecords(saving: recordList, deleting: [], savePolicy: .allKeys, atomically: false)

                for updateResult in outcome.saveResults {
                    let uuid = updateResult.key.recordName
                    switch updateResult.value {
                    case let .success(record):
                        log("Confirmed cloud save of item \(record.recordType) id (\(uuid))")

                        if uuid == CloudManager.RecordType.positionList.rawValue {
                            Task { @CloudActor in
                                CloudManager.uuidSequence = currentUUIDSequence
                                CloudManager.uuidSequenceRecord = record
                            }

                        } else if let item = await DropStore.item(uuid: uuid) {
                            await item.setCloudKitRecord(record)
                            dropsToPush -= 1

                        } else if let component = await DropStore.component(uuid: uuid) {
                            await component.setCloudKitRecord(record)
                            componentsToPush -= 1
                        }

                    case let .failure(error):
                        log("Error in cloud save of item (\(uuid)): \(error.localizedDescription)")
                    }
                }
                updateSyncMessage()
            }

            if recordIdsToDelete.isPopulated {
                let outcome = try await database.modifyRecords(saving: [], deleting: recordIdsToDelete, savePolicy: .allKeys, atomically: false)

                var deletedRecordIds = [String]()
                for deletionResult in outcome.deleteResults {
                    let uuid = deletionResult.key.recordName
                    switch deletionResult.value {
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
                log("Item cloud deletions completed")
                await CloudManager.commitDeletion(for: deletedRecordIds)
                updateSyncMessage()
            }

        } catch {
            updateSyncMessage()
            log("Error updating cloud records: \(error.localizedDescription)")
            throw error
        }
    }
}
