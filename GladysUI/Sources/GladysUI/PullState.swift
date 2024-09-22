import CloudKit
import GladysCommon
import Lista
import PopTimer

final actor PullState {
    private enum ZoneModification {
        case itemModified(modification: CKDatabase.RecordZoneChange.Modification)
        case itemDeleted(deletion: CKDatabase.RecordZoneChange.Deletion)
        case setZoneToken(zoneToken: CKServerChangeToken?, zoneId: CKRecordZone.ID)
    }

    private var newDropCount = 0 { didSet { updateProgress() } }
    private var newTypeItemCount = 0 { didSet { updateProgress() } }

    private var typeUpdateCount = 0 { didSet { updateProgress() } }
    private var deletionCount = 0 { didSet { updateProgress() } }
    private var updateCount = 0 { didSet { updateProgress() } }
    private var newTypesAppended = 0

    private var updatedDatabaseTokens = [CKDatabase.Scope: CKServerChangeToken]()
    private var updatedZoneTokens = [CKRecordZone.ID: CKServerChangeToken]()
    private var pendingShareComponentRecords = [CKRecord.ID: CKShare]() // using full IDs because zone is also imporant
    private var pendingComponentRecords = [CKRecord.ID: Lista<CKRecord>]() // using full IDs because zone is also imporant
    private let newItemsDebounce = PopTimer(timeInterval: 0.3) {
        sendNotification(name: .ItemsAddedBySync)
    }

    private func updateProgress() {
        Task {
            await _updateProgress()
        }
    }

    private func _updateProgress() async {
        let components = Lista<String>()

        if newDropCount > 0 { components.append(newDropCount == 1 ? "1 Drop" : "\(newDropCount) Drops") }
        if updateCount > 0 { components.append(updateCount == 1 ? "1 Update" : "\(updateCount) Updates") }
        if newTypeItemCount > 0 { components.append(newTypeItemCount == 1 ? "1 Component" : "\(newTypeItemCount) Components") }
        if typeUpdateCount > 0 { components.append(typeUpdateCount == 1 ? "1 Component Update" : "\(typeUpdateCount) Component Updates") }
        if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }

        if components.count == 0 {
            await CloudManager.setSyncProgressString("Fetching")
        } else {
            await CloudManager.setSyncProgressString("Fetched " + components.joined(separator: ", "))
        }
    }

    private func processChanges(commitTokens: Bool) async {
        newItemsDebounce.abort()
        await CloudManager.setSyncProgressString("Updating…")
        log("Changes fetch complete, processing")

        let haveNewlyContrustedItems = await DropStore.syncDone()

        let needsSave = haveNewlyContrustedItems || updatedZoneTokens.isPopulated

        if needsSave {
            await Model.sortDrops()
            await Model.save(dueToSyncFetch: true)

        } else {
            log("No updates available")
        }

        if commitTokens {
            for (zoneId, zoneToken) in updatedZoneTokens {
                log("Committing zone token")
                setZoneToken(zoneToken, for: zoneId)
            }
            for (databaseId, databaseToken) in updatedDatabaseTokens {
                log("Committing DB token")
                setDatabaseToken(databaseToken, for: databaseId)
            }
        }
    }

    ///////////////////////////////////////

    @UserDefault(key: "zoneTokens", defaultValue: [String: Data]())
    private var zoneTokens: [String: Data]

    static func wipeZoneTokens() {
        PersistedOptions.defaults.removeObject(forKey: "zoneTokens")
    }

    private func zoneToken(for zoneId: CKRecordZone.ID) -> CKServerChangeToken? {
        if let data = zoneTokens[zoneId.ownerName + ":" + zoneId.zoneName] {
            return SafeArchiving.unarchive(data) as? CKServerChangeToken
        }
        return nil
    }

    private func setZoneToken(_ token: CKServerChangeToken?, for zoneId: CKRecordZone.ID) {
        let key = zoneId.ownerName + ":" + zoneId.zoneName
        if let n = token {
            zoneTokens[key] = SafeArchiving.archive(n)
        } else {
            zoneTokens[key] = nil
        }
    }

    ///////////////////////////////////////

    @UserDefault(key: "databaseTokens", defaultValue: [String: Data]())
    private var databaseTokens: [String: Data]

    static func wipeDatabaseTokens() {
        PersistedOptions.defaults.removeObject(forKey: "databaseTokens")
    }

    private func databaseToken(for database: CKDatabase.Scope) -> CKServerChangeToken? {
        if let data = databaseTokens[database.keyName] {
            return SafeArchiving.unarchive(data) as? CKServerChangeToken
        }
        return nil
    }

    private func setDatabaseToken(_ token: CKServerChangeToken?, for database: CKDatabase.Scope) {
        if let n = token {
            databaseTokens[database.keyName] = SafeArchiving.archive(n)
        } else {
            databaseTokens[database.keyName] = nil
        }
    }

    private func recordDeleted(recordId: CKRecord.ID, recordType: CloudManager.RecordType) async {
        let itemUUID = recordId.recordName
        switch recordType {
        case .item:
            if let item = await DropStore.item(uuid: itemUUID) {
                if await item.parentZone != recordId.zoneID {
                    log("Ignoring delete for item \(itemUUID) from a different zone")
                } else {
                    log("Item deletion: \(itemUUID)")
                    await item.setStatus(.deleted)
                    await item.setCloudKitRecord(nil) // no need to sync deletion up, it's already recorded in the cloud
                    await item.setCloudKitShareRecord(nil) // get rid of useless file
                    deletionCount += 1
                }
            } else {
                log("Received delete for non-existent item record \(itemUUID), ignoring")
            }
        case .component:
            if let component = await DropStore.component(uuid: itemUUID) {
                let componentParentZone = await component.parentZone
                if componentParentZone != recordId.zoneID {
                    log("Ignoring delete for component \(itemUUID) from a different zone")
                } else {
                    log("Component deletion: \(itemUUID)")
                    await component.setNeedsDeletion(true)
                    await component.setCloudKitRecord(nil) // no need to sync deletion up, it's already recorded in the cloud
                    deletionCount += 1
                }
            } else {
                log("Received delete for non-existent component record \(itemUUID), ignoring")
            }
        case .share:
            if let associatedItem = await (MainActor.run { DropStore.item(shareId: itemUUID) }) {
                if let zoneID = await associatedItem.cloudKitShareRecord?.recordID.zoneID, zoneID != recordId.zoneID {
                    log("Ignoring delete for share record for item \(associatedItem.uuid) from a different zone")
                } else {
                    log("Share record deleted for item \(associatedItem.uuid)")
                    await associatedItem.setCloudKitShareRecord(nil)
                    deletionCount += 1
                }
            } else {
                log("Received delete for non-existent share record \(itemUUID), ignoring")
            }
        case .positionList:
            log("Positionlist record deletion detected")
        case .extensionUpdate:
            log("Extension record deletion detected")
        }
    }

    private func fetchZoneChanges(database: CKDatabase, zoneIDs: [CKRecordZone.ID]) async throws {
        log("Fetching changes to \(zoneIDs.count) zone(s) in \(database.databaseScope.logName) database")

        let changeQueue = AsyncStream<ZoneModification>.makeStream()
        let neverSynced = await CloudManager.lastSyncCompletion == .distantPast

        let queueTask = Task {
            for await change in changeQueue.stream {
                switch change {
                case let .itemModified(modification):
                    let record = modification.record
                    if let type = CloudManager.RecordType(rawValue: record.recordType) {
                        await recordChanged(record: record, recordType: type, neverSynced: neverSynced)
                    }
                case let .itemDeleted(deletion):
                    if let type = CloudManager.RecordType(rawValue: deletion.recordType) {
                        await recordDeleted(recordId: deletion.recordID, recordType: type)
                    }
                case let .setZoneToken(zoneToken, zoneId):
                    setUpdatedZoneToken(zoneToken, for: zoneId)
                }
            }
        }

        try await withThrowingDiscardingTaskGroup { taskGroup in
            for zoneID in zoneIDs {
                taskGroup.addTask {
                    var zoneToken = await self.zoneToken(for: zoneID)
                    var moreComing = true
                    while moreComing {
                        let zoneChangesResults: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                                                 deletions: [CKDatabase.RecordZoneChange.Deletion],
                                                 changeToken: CKServerChangeToken,
                                                 moreComing: Bool)?
                        do {
                            zoneChangesResults = try await database.recordZoneChanges(inZoneWith: zoneID, since: zoneToken)
                        } catch {
                            if error.changeTokenExpired {
                                zoneToken = nil
                                await CloudManager.setSyncProgressString("Fetching Full Update…")
                                log("Zone \(zoneID.zoneName) changes fetch had stale token, will retry")
                                continue
                            } else {
                                throw error
                            }
                        }

                        guard let zoneChangesResults else { return }

                        for (recordId, fetchResult) in zoneChangesResults.modificationResultsByID {
                            switch fetchResult {
                            case let .success(modification):
                                changeQueue.continuation.yield(.itemModified(modification: modification))
                            case let .failure(error):
                                log("Changes could not be fetched for record \(recordId): \(error.localizedDescription)")
                            }
                        }

                        for deletion in zoneChangesResults.deletions {
                            changeQueue.continuation.yield(.itemDeleted(deletion: deletion))
                        }

                        zoneToken = zoneChangesResults.changeToken
                        moreComing = zoneChangesResults.moreComing
                    }

                    changeQueue.continuation.yield(.setZoneToken(zoneToken: zoneToken, zoneId: zoneID))
                }
            }
        }

        changeQueue.continuation.finish()
        _ = await queueTask.value
    }

    private func setUpdatedZoneToken(_ token: CKServerChangeToken?, for zoneId: CKRecordZone.ID) {
        updatedZoneTokens[zoneId] = token
    }

    private func fetchDBChanges(database: CKDatabase) async throws -> Bool {
        var changedZoneIds = Set<CKRecordZone.ID>()
        var deletedZoneIds = Set<CKRecordZone.ID>()
        var databaseToken = databaseToken(for: database.databaseScope)

        var moreComing = true
        while moreComing {
            var databaseChanges: (modifications: [CKDatabase.DatabaseChange.Modification],
                                  deletions: [CKDatabase.DatabaseChange.Deletion],
                                  changeToken: CKServerChangeToken,
                                  moreComing: Bool)?
            do {
                databaseChanges = try await database.databaseChanges(since: databaseToken)
            } catch {
                if error.changeTokenExpired {
                    databaseToken = nil
                    log("Database \(database.databaseScope.logName) changes fetch had stale token, will retry")
                    await CloudManager.setSyncProgressString("Fetching Full Update…")
                    continue
                } else {
                    log("\(database.databaseScope.logName) database fetch operation failed: \(error.localizedDescription)")
                    throw error
                }
            }

            guard let databaseChanges else {
                throw GladysError.noData
            }

            for modification in databaseChanges.modifications {
                changedZoneIds.insert(modification.zoneID)
            }
            for deletion in databaseChanges.deletions {
                deletedZoneIds.insert(deletion.zoneID)
                if deletion.reason == .purged {
                    log("Detected zone purging in \(deletion.zoneID.zoneName) database: \(database.databaseScope.logName)")
                } else {
                    log("Detected zone deletion in \(deletion.zoneID.zoneName) database: \(database.databaseScope.logName)")
                }
            }
            databaseToken = databaseChanges.changeToken
            moreComing = databaseChanges.moreComing
        }

        if deletedZoneIds.contains(privateZoneId) {
            if database.databaseScope == .private {
                log("Private zone has been deleted, sync must be disabled.")
                try? await CloudManager.deactivate(force: true)
                throw GladysError.cloudLogoutDetected
            } else {
                log("Private zone has been signaled as deleted in \(database.databaseScope.logName) database, ignoring this")
                deletedZoneIds.remove(privateZoneId)
            }
        }

        for deletedZoneId in deletedZoneIds {
            log("Handling zone deletion in \(database.databaseScope.logName) database: \(deletedZoneId)")
            await Model.removeItemsFromZone(deletedZoneId)
            setZoneToken(nil, for: deletedZoneId)
        }

        if changedZoneIds.isEmpty {
            log("No database changes detected in \(database.databaseScope.logName) database")
            updatedDatabaseTokens[database.databaseScope] = databaseToken
            return false
        }

        do {
            try await fetchZoneChanges(database: database, zoneIDs: Array(changedZoneIds))
            updatedDatabaseTokens[database.databaseScope] = databaseToken
        } catch {
            log("Error fetching zone changes for \(database.databaseScope.logName) database: \(error.localizedDescription)")
        }
        return false
    }

    func fetchDatabaseChanges(scope: CKDatabase.Scope?) async throws {
        await CloudManager.setSyncProgressString("Checking…")

        do {
            let skipCommits = try await withThrowingTaskGroup(of: Bool.self, returning: Bool.self) { group in
                if scope == nil || scope == .private {
                    group.addTask {
                        try await self.fetchDBChanges(database: CloudManager.container.privateCloudDatabase)
                    }
                }

                if scope == nil || scope == .shared {
                    group.addTask {
                        try await self.fetchDBChanges(database: CloudManager.container.sharedCloudDatabase)
                    }
                }

                return try await group.contains(true)
            }

            try? await CloudManager.fetchMissingShareRecords()
            await processChanges(commitTokens: !skipCommits)

        } catch {
            await processChanges(commitTokens: false)
            throw error
        }
    }

    private func recordChanged(record: CKRecord, recordType: CloudManager.RecordType, neverSynced: Bool) async {
        let recordID = record.recordID
        let zoneID = recordID.zoneID
        let recordUUID = recordID.recordName
        switch recordType {
        case .item:
            if let item = await DropStore.item(uuid: recordUUID) {
                if await item.parentZone != zoneID {
                    log("Ignoring update notification for existing item UUID but wrong zone (\(recordUUID))")
                } else {
                    switch await RecordChangeCheck(localRecord: item.cloudKitRecord, remoteRecord: record) {
                    case .changed:
                        log("Will update existing local item for cloud record \(recordUUID)")
                        await item.cloudKitUpdate(from: record)
                        updateCount += 1
                    case .tagOnly:
                        log("Update but no changes to item record (\(recordUUID)) apart from tag")
                        await item.setCloudKitRecord(record)
                    case .none:
                        log("Update but no changes to item record (\(recordUUID))")
                    }
                }

            } else {
                log("Will create new local item for cloud record (\(recordUUID)) - pending count: \(pendingComponentRecords.count)")
                let newItem = await ArchivedItem(from: record)
                let newTypeItemRecords = pendingComponentRecords.removeValue(forKey: recordID)
                if let newTypeItemRecords {
                    let uuid = newItem.uuid
                    let newComponents = await newTypeItemRecords.asyncMap { await Component(from: $0, parentUuid: uuid) }
                    await newItem.setComponents(ContiguousArray(newComponents))
                    log("  Hooked \(newTypeItemRecords.count) pending type items")
                }
                if let existingShareId = record.share?.recordID, let pendingShareRecord = pendingShareComponentRecords.removeValue(forKey: existingShareId) {
                    await newItem.setCloudKitShareRecord(pendingShareRecord)
                    log("  Hooked onto pending share \(existingShareId.recordName)")
                }
                await DropStore.append(drop: newItem)
                newDropCount += 1
                newItemsDebounce.push()
            }

        case .component:
            if let component = await DropStore.component(uuid: recordUUID) {
                if await (component.parentZone) != zoneID {
                    log("Ignoring update notification for existing component UUID but wrong zone (\(recordUUID))")
                } else {
                    switch await RecordChangeCheck(localRecord: component.cloudKitRecord, remoteRecord: record) {
                    case .changed:
                        log("Will update existing component: (\(recordUUID))")
                        await component.cloudKitUpdate(from: record)
                        typeUpdateCount += 1
                    case .tagOnly:
                        log("Update but no changes to item type data record (\(recordUUID)) apart from tag")
                        await component.setCloudKitRecord(record)
                    case .none:
                        log("Update but no changes to item type data record (\(recordUUID))")
                    }
                }
            } else if let parentId = record.parent?.recordID {
                if let existingParent = await DropStore.item(uuid: parentId.recordName) {
                    if await existingParent.parentZone != zoneID {
                        log("Ignoring new component for existing item UUID but wrong zone (component: \(recordUUID) item: \(parentId.recordName))")
                    } else {
                        log("Will create new component (\(recordUUID)) for parent (\(parentId.recordName))")
                        let newComponent = await Component(from: record, parentUuid: existingParent.uuid)
                        await existingParent.appendComponent(newComponent)
                        newTypeItemCount += 1
                    }
                } else {
                    if let pending = pendingComponentRecords[parentId] {
                        pending.append(record)
                    } else {
                        pendingComponentRecords[parentId] = Lista(value: record)
                    }
                    log("Received new type item (\(recordUUID)) to link to upcoming new item (\(parentId.recordName))")
                }
            }

        case .positionList:
            let change = await RecordChangeCheck(localRecord: CloudManager.uuidSequenceRecord, remoteRecord: record)
            if change == .changed || neverSynced {
                log("Received an updated position list record")
                let newList = (record["positionList"] as? [String]) ?? []
                Task { @CloudActor in
                    CloudManager.uuidSequence = newList
                    CloudManager.uuidSequenceRecord = record
                }
            } else if change == .tagOnly {
                log("Received non-updated position list record, updated tag")
                Task { @CloudActor in
                    CloudManager.uuidSequenceRecord = record
                }
            } else {
                log("Received non-updated position list record")
            }

        case .share:
            if let share = record as? CKShare {
                if let associatedItem = await DropStore.item(shareId: recordUUID) {
                    if await associatedItem.parentZone != zoneID {
                        log("Ignoring share record updated for existing item in different zone (share: \(recordUUID) - item: \(associatedItem.uuid))")
                    } else {
                        log("Share record updated for item (share: \(recordUUID) - item: \(associatedItem.uuid))")
                        await associatedItem.setCloudKitShareRecord(share)
                        updateCount += 1
                    }
                } else {
                    pendingShareComponentRecords[recordID] = share
                    log("Received new share record (\(recordUUID)) to potentially link to upcoming new item")
                }
            }

        case .extensionUpdate:
            log("Received an extension update record")
            await MainActor.run {
                PersistedOptions.extensionRequestedSync = false
            }
        }
    }
}
