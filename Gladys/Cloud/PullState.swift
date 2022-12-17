import CloudKit
import GladysFramework

final actor PullState {
    var updatedSequence = false
    var newDropCount = 0 { didSet { updateProgress() } }
    var newTypeItemCount = 0 { didSet { updateProgress() } }

    var typeUpdateCount = 0 { didSet { updateProgress() } }
    var deletionCount = 0 { didSet { updateProgress() } }
    var updateCount = 0 { didSet { updateProgress() } }
    var newTypesAppended = 0

    var updatedDatabaseTokens = [CKDatabase.Scope: CKServerChangeToken]()
    var updatedZoneTokens = [CKRecordZone.ID: CKServerChangeToken]()
    var pendingShareRecords = Set<CKShare>()
    var pendingTypeItemRecords = Set<CKRecord>()

    private func updateProgress() {
        Task {
            await _updateProgress()
        }
    }

    private func _updateProgress() async {
        var components = [String]()

        if newDropCount > 0 { components.append(newDropCount == 1 ? "1 Drop" : "\(newDropCount) Drops") }
        if updateCount > 0 { components.append(updateCount == 1 ? "1 Update" : "\(updateCount) Updates") }
        if newTypeItemCount > 0 { components.append(newTypeItemCount == 1 ? "1 Component" : "\(newTypeItemCount) Components") }
        if typeUpdateCount > 0 { components.append(typeUpdateCount == 1 ? "1 Component Update" : "\(typeUpdateCount) Component Updates") }
        if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }

        if components.isEmpty {
            await CloudManager.setSyncProgressString("Fetching")
        } else {
            await CloudManager.setSyncProgressString("Fetched " + components.joined(separator: ", "))
        }
    }

    private func processChanges(commitTokens: Bool) async {
        await CloudManager.setSyncProgressString("Updating…")
        log("Changes fetch complete, processing")

        if updatedSequence || newDropCount > 0 {
            Task { @MainActor in
                Model.sortDrops()
            }
        }

        let itemsModified = typeUpdateCount + newDropCount + updateCount + deletionCount + newTypesAppended > 0

        if itemsModified {
            // need to save stuff that's been modified
            Task { @MainActor in
                Model.saveIsDueToSyncFetch = true
                Model.save()
            }

        } else if !updatedZoneTokens.isEmpty, updatedSequence {
            // a position record, most likely?
            Task { @MainActor in
                Model.saveIsDueToSyncFetch = true
                Model.saveIndexOnly()
            }

        } else {
            log("No updates available")
        }

        if commitTokens {
            if !updatedZoneTokens.isEmpty || !updatedDatabaseTokens.isEmpty {
                log("Committing change tokens")
            }
            for (zoneId, zoneToken) in updatedZoneTokens {
                setZoneToken(zoneToken, for: zoneId)
            }
            for (databaseId, databaseToken) in updatedDatabaseTokens {
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
            if let item = (await MainActor.run { Model.item(uuid: itemUUID) }) {
                if item.parentZone != recordId.zoneID {
                    log("Ignoring delete for item \(itemUUID) from a different zone")
                } else {
                    log("Item deletion: \(itemUUID)")
                    item.needsDeletion = true
                    item.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
                    item.cloudKitShareRecord = nil // get rid of useless file
                    deletionCount += 1
                }
            } else {
                log("Received delete for non-existent item record \(itemUUID), ignoring")
            }
        case .component:
            if let component = await Model.component(uuid: itemUUID) {
                let componentParentZone = await component.parentZone
                if componentParentZone != recordId.zoneID {
                    log("Ignoring delete for component \(itemUUID) from a different zone")
                } else {
                    log("Component deletion: \(itemUUID)")
                    component.needsDeletion = true
                    component.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
                    deletionCount += 1
                }
            } else {
                log("Received delete for non-existent component record \(itemUUID), ignoring")
            }
        case .share:
            if let associatedItem = (await MainActor.run { Model.item(shareId: itemUUID) }) {
                if let zoneID = associatedItem.cloudKitShareRecord?.recordID.zoneID, zoneID != recordId.zoneID {
                    log("Ignoring delete for share record for item \(associatedItem.uuid) from a different zone")
                } else {
                    log("Share record deleted for item \(associatedItem.uuid)")
                    associatedItem.cloudKitShareRecord = nil
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

        let neverSynced = await CloudManager.lastSyncCompletion == .distantPast
        
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for zoneID in zoneIDs {
                taskGroup.addTask {
                    var zoneToken = await self.zoneToken(for: zoneID)
                    var moreComing = true
                    while moreComing {
                        var zoneChangesResults: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                                                 deletions: [CKDatabase.RecordZoneChange.Deletion],
                                                 changeToken: CKServerChangeToken,
                                                 moreComing: Bool)?
                        var go = true
                        while go {
                            do {
                                zoneChangesResults = try await database.recordZoneChanges(inZoneWith: zoneID, since: zoneToken)
                                go = false
                            } catch {
                                if (error as? CKError)?.code == .changeTokenExpired {
                                    zoneToken = nil
                                    await CloudManager.setSyncProgressString("Fetching Full Update…")
                                    log("Zone \(zoneID.zoneName) changes fetch had stale token, will retry")
                                } else {
                                    throw error
                                }
                            }
                        }
                        
                        guard let zoneChangesResults else { return }
                        
                        for (recordId, fetchResult) in zoneChangesResults.modificationResultsByID {
                            switch fetchResult {
                            case .success(let modification):
                                let record = modification.record
                                if let type = CloudManager.RecordType(rawValue: record.recordType) {
                                    await self.recordChanged(record: record, recordType: type, neverSynced: neverSynced)
                                }
                            case .failure(let error):
                                log("Changes could not be fetched for record \(recordId): \(error.finalDescription)")
                            }
                        }
                        
                        for deletion in zoneChangesResults.deletions {
                            if let type = CloudManager.RecordType(rawValue: deletion.recordType) {
                                await self.recordDeleted(recordId: deletion.recordID, recordType: type)
                            }
                        }
                        
                        zoneToken = zoneChangesResults.changeToken
                        moreComing = zoneChangesResults.moreComing
                    }
                    
                    await self.setZoneToken(zoneToken, for: zoneID)
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func fetchDBChanges(database: CKDatabase) async throws -> Bool {
        var changedZoneIds = Set<CKRecordZone.ID>()
        var deletedZoneIds = Set<CKRecordZone.ID>()
        let databaseToken = databaseToken(for: database.databaseScope)
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseToken)
        operation.recordZoneWithIDChangedBlock = { changedZoneIds.insert($0) }
        operation.recordZoneWithIDWasPurgedBlock = {
            deletedZoneIds.insert($0)
            log("Detected zone purging in \(database.databaseScope.logName) database: \($0)")
        }
        operation.recordZoneWithIDWasDeletedBlock = {
            deletedZoneIds.insert($0)
            log("Detected zone deletion in \(database.databaseScope.logName) database: \($0)")
        }

        let newToken = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKServerChangeToken, Error>) in
            operation.fetchDatabaseChangesCompletionBlock = { newToken, _, error in
                if let newToken {
                    continuation.resume(returning: newToken)
                    return
                }
                let err = error ?? GladysError.blankResponse.error
                log("\(database.databaseScope.logName) database fetch operation failed: \(err.finalDescription)")
                continuation.resume(throwing: err)
            }
            CloudManager.submit(operation, on: database, type: "fetch database changes")
        }

        if deletedZoneIds.contains(privateZoneId) {
            if database.databaseScope == .private {
                log("Private zone has been deleted, sync must be disabled.")
                await genericAlert(title: "Your Gladys iCloud zone was deleted from another device.", message: "Sync was disabled in order to protect the data on this device.\n\nYou can re-create your iCloud data store with data from here if you turn sync back on again.")
                try await CloudManager.deactivate(force: true)
                return true
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
            updatedDatabaseTokens[database.databaseScope] = newToken
            return false
        }

        do {
            try await fetchZoneChanges(database: database, zoneIDs: Array(changedZoneIds))
            updatedDatabaseTokens[database.databaseScope] = newToken
        } catch {
            log("Error fetching zone changes for \(database.databaseScope.logName) database: \(error.finalDescription)")
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

                return try await group.contains { $0 == true }
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
            if let item = await Model.item(uuid: recordUUID) {
                if item.parentZone != zoneID {
                    log("Ignoring update notification for existing item UUID but wrong zone (\(recordUUID))")
                } else {
                    switch RecordChangeCheck(localRecord: item.cloudKitRecord, remoteRecord: record) {
                    case .changed:
                        log("Will update existing local item for cloud record \(recordUUID)")
                        item.cloudKitUpdate(from: record)
                        updateCount += 1
                    case .tagOnly:
                        log("Update but no changes to item record (\(recordUUID)) apart from tag")
                        item.cloudKitRecord = record
                    case .none:
                        log("Update but no changes to item record (\(recordUUID))")
                    }
                }

            } else {
                log("Will create new local item for cloud record (\(recordUUID)) - pendingTypeItemRecords count: \(pendingTypeItemRecords.count)")
                let newItem = ArchivedItem(from: record)
                let newTypeItemRecords = pendingTypeItemRecords.filter {
                    $0.parent?.recordID == recordID // takes zone into account
                }
                if !newTypeItemRecords.isEmpty {
                    pendingTypeItemRecords.subtract(newTypeItemRecords)
                    let uuid = newItem.uuid
                    let newComponents = newTypeItemRecords.map { Component(from: $0, parentUuid: uuid) }
                    newItem.components.append(contentsOf: newComponents)
                    log("  Hooked \(newTypeItemRecords.count) pending type items")
                }
                if let existingShareId = record.share?.recordID, let pendingShareRecord = pendingShareRecords.first(where: {
                    $0.recordID == existingShareId // takes zone into account
                }) {
                    newItem.cloudKitShareRecord = pendingShareRecord
                    pendingShareRecords.remove(pendingShareRecord)
                    log("  Hooked onto pending share \(existingShareId.recordName)")
                }
                await Model.append(drop: newItem)
                newDropCount += 1
                Task { @MainActor in
                    sendNotification(name: .ItemAddedBySync, object: newItem)
                }
            }

        case .component:
            if let typeItem = await Model.component(uuid: recordUUID) {
                if (await typeItem.parentZone) != zoneID {
                    log("Ignoring update notification for existing component UUID but wrong zone (\(recordUUID))")
                } else {
                    switch RecordChangeCheck(localRecord: typeItem.cloudKitRecord, remoteRecord: record) {
                    case .changed:
                        log("Will update existing component: (\(recordUUID))")
                        typeItem.cloudKitUpdate(from: record)
                        typeUpdateCount += 1
                    case .tagOnly:
                        log("Update but no changes to item type data record (\(recordUUID)) apart from tag")
                        typeItem.cloudKitRecord = record
                    case .none:
                        log("Update but no changes to item type data record (\(recordUUID))")
                    }
                }
            } else if let parentId = (record["parent"] as? CKRecord.Reference)?.recordID.recordName, let existingParent = await Model.item(uuid: parentId) {
                if existingParent.parentZone != zoneID {
                    log("Ignoring new component for existing item UUID but wrong zone (component: \(recordUUID) item: \(parentId))")
                } else {
                    log("Will create new component (\(recordUUID)) for parent (\(parentId))")
                    existingParent.components.append(Component(from: record, parentUuid: existingParent.uuid))
                    newTypeItemCount += 1
                }
            } else {
                pendingTypeItemRecords.insert(record)
                log("Received new type item (\(recordUUID)) to link to upcoming new item")
            }

        case .positionList:
            let change = RecordChangeCheck(localRecord: await CloudManager.uuidSequenceRecord, remoteRecord: record)
            if change == .changed || neverSynced {
                log("Received an updated position list record")
                let newList = (record["positionList"] as? [String]) ?? []
                await CloudManager.setUuidSequenceAsync(newList)
                updatedSequence = true
                await CloudManager.setUuidSequenceRecordAsync(record)
            } else if change == .tagOnly {
                log("Received non-updated position list record, updated tag")
                await CloudManager.setUuidSequenceRecordAsync(record)
            } else {
                log("Received non-updated position list record")
            }

        case .share:
            if let share = record as? CKShare {
                if let associatedItem = await Model.item(shareId: recordUUID) {
                    if associatedItem.parentZone != zoneID {
                        log("Ignoring share record updated for existing item in different zone (share: \(recordUUID) - item: \(associatedItem.uuid))")
                    } else {
                        log("Share record updated for item (share: \(recordUUID) - item: \(associatedItem.uuid))")
                        associatedItem.cloudKitShareRecord = share
                        updateCount += 1
                    }
                } else {
                    pendingShareRecords.insert(share)
                    log("Received new share record (\(recordUUID)) to potentially link to upcoming new item")
                }
            }

        case .extensionUpdate:
            log("Received an extension update record")
            PersistedOptions.extensionRequestedSync = false
        }
    }
}
