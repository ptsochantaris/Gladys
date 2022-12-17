#if os(iOS)
    import UIKit
#else
    import Cocoa
#endif
import CloudKit
import GladysFramework

extension CloudManager {
    static let privateDatabaseSubscriptionId = "private-changes"
    static let sharedDatabaseSubscriptionId = "shared-changes"
    static var syncDirty = false

    nonisolated static func submit(_ operation: CKDatabaseOperation, on database: CKDatabase, type: String) {
        log("CK \(database.databaseScope.logName) database, operation \(operation.operationID): \(type)")
        operation.qualityOfService = .userInitiated
        database.add(operation)
    }
    
    static var showNetwork = false {
        didSet {
            Model.updateBadge()
        }
    }

    private(set) static var syncProgressString: String?

    private static let syncProgressDebouncer = PopTimer(timeInterval: 0.2) {
        #if DEBUG
            if let s = syncProgressString {
                log(">>> Sync label updated: \(s)")
            } else {
                log(">>> Sync label cleared")
            }
        #endif
        sendNotification(name: .CloudManagerStatusChanged, object: nil)
    }

    static func setSyncProgressString(_ newString: String?) {
        syncProgressString = newString
        syncProgressDebouncer.push()
    }

    private static func sendUpdatesUp() async throws {
        if !syncSwitchedOn {
            return
        }

        var sharedZonesToPush = Set<CKRecordZone.ID>()
        for item in Model.allDrops where item.needsCloudPush {
            let zoneID = item.parentZone
            if zoneID != privateZoneId {
                sharedZonesToPush.insert(zoneID)
            }
        }

        for deletionEntry in deletionQueue {
            let components = deletionEntry.components(separatedBy: ":")
            if components.count > 2 {
                let zoneID = CKRecordZone.ID(zoneName: components[0], ownerName: components[1])
                if zoneID != privateZoneId {
                    sharedZonesToPush.insert(zoneID)
                }
            }
        }

        let privatePushState = await PushState(zoneId: privateZoneId, database: container.privateCloudDatabase)

        var _sharedPushStates = [PushState]()
        _sharedPushStates.reserveCapacity(sharedZonesToPush.count)
        for sharedZoneId in sharedZonesToPush {
            let pushState = await PushState(zoneId: sharedZoneId, database: container.sharedCloudDatabase)
            _sharedPushStates.append(pushState)
        }
        let sharedPushStates = _sharedPushStates

        var operations = await privatePushState.operations
        for sharedPushState in sharedPushStates {
            operations.append(contentsOf: await sharedPushState.operations)
        }

        if operations.isEmpty {
            log("No changes to push up")
            return
        }

        await withCheckedContinuation { continuation in
            let done = BlockOperation {
                continuation.resume()
            }

            for operation in operations {
                done.addDependency(operation)
                submit(operation, on: operation.database!, type: "sync upload")
            }
            
            let queue = OperationQueue.current ?? OperationQueue.main
            queue.addOperation(done)
        }

        if let error = await privatePushState.latestError {
            throw error
        }

        for pushState in sharedPushStates {
            if let error = await pushState.latestError {
                throw error
            }
        }
    }

    static var syncTransitioning = false {
        didSet {
            if syncTransitioning != oldValue {
                showNetwork = syncing || syncTransitioning
                sendNotification(name: .CloudManagerStatusChanged, object: nil)
            }
        }
    }

    static var syncRateLimited = false {
        didSet {
            if syncTransitioning != oldValue {
                Task {
                    setSyncProgressString(syncing ? "Pausing" : nil)
                }
                showNetwork = false
                sendNotification(name: .CloudManagerStatusChanged, object: nil)
            }
        }
    }

    static var syncing = false {
        didSet {
            if syncing != oldValue {
                Task {
                    setSyncProgressString(syncing ? "Syncing" : nil)
                }
                showNetwork = syncing || syncTransitioning
                sendNotification(name: .CloudManagerStatusChanged, object: nil)
            }
        }
    }

    typealias ICloudToken = (NSCoding & NSCopying & NSObjectProtocol)
    static var lastiCloudAccount: ICloudToken? {
        get {
            let o = PersistedOptions.defaults.object(forKey: "lastiCloudAccount") as? ICloudToken
            return (o?.isEqual("") ?? false) ? nil : o
        }
        set {
            if let n = newValue {
                PersistedOptions.defaults.set(n, forKey: "lastiCloudAccount")
            } else {
                PersistedOptions.defaults.set("", forKey: "lastiCloudAccount") // this will return nil when fetched
            }
        }
    }

    @UserDefault(key: "lastSyncCompletion", defaultValue: .distantPast)
    static var lastSyncCompletion: Date

    static var uuidSequence: [String] {
        get {
            if let data = PersistedOptions.defaults.data(forKey: "uuidSequence") {
                return SafeArchiving.unarchive(data) as? [String] ?? []
            } else {
                return []
            }
        }
        set {
            if let data = SafeArchiving.archive(newValue) {
                PersistedOptions.defaults.set(data, forKey: "uuidSequence")
            }
        }
    }

    static func setUuidSequenceAsync(_ newList: [String]) {
        uuidSequence = newList
    }

    static func setUuidSequenceRecordAsync(_ newRecord: CKRecord?) {
        uuidSequenceRecord = newRecord
    }

    static var uuidSequenceRecordPath: URL {
        Model.appStorageUrl.appendingPathComponent("ck-uuid-sequence", isDirectory: false)
    }

    static var uuidSequenceRecord: CKRecord? {
        get {
            if let data = try? Data(contentsOf: uuidSequenceRecordPath), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
                let record = CKRecord(coder: coder)
                coder.finishDecoding()
                return record
            } else {
                return nil
            }
        }
        set {
            let recordLocation = uuidSequenceRecordPath
            if let newValue {
                let coder = NSKeyedArchiver(requiringSecureCoding: true)
                newValue.encodeSystemFields(with: coder)
                try? coder.encodedData.write(to: recordLocation)
            } else {
                let f = FileManager.default
                let p = recordLocation.path
                if f.fileExists(atPath: p) {
                    try? f.removeItem(atPath: p)
                }
            }
        }
    }

    static var deleteQueuePath: URL {
        Model.appStorageUrl.appendingPathComponent("ck-delete-queue", isDirectory: false)
    }

    static var deletionQueue: Set<String> {
        get {
            if let data = try? Data(contentsOf: deleteQueuePath) {
                return SafeArchiving.unarchive(data) as? Set<String> ?? []
            } else {
                return []
            }
        }
        set {
            try? SafeArchiving.archive(newValue)?.write(to: deleteQueuePath)
        }
    }

    static func setDeletionQueueAsync(_ newQueue: Set<String>) {
        deletionQueue = newQueue
    }

    private static func deletionTag(for recordName: String, cloudKitRecord: CKRecord?) -> String {
        if let zoneId = cloudKitRecord?.recordID.zoneID {
            return zoneId.zoneName + ":" + zoneId.ownerName + ":" + recordName
        } else {
            return recordName
        }
    }

    static func markAsDeleted(recordName: String, cloudKitRecord: CKRecord?) {
        if syncSwitchedOn {
            deletionQueue.insert(deletionTag(for: recordName, cloudKitRecord: cloudKitRecord))
        }
    }

    static func commitDeletion(for recordNames: [String]) {
        if recordNames.isEmpty { return }

        CloudManager.deletionQueue = CloudManager.deletionQueue.filter {
            if let lastPartOfTag = $0.components(separatedBy: ":").last {
                return !recordNames.contains(lastPartOfTag)
            } else {
                return true
            }
        }
    }

    private static let agoFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    static var syncString: String {
        if let s = syncProgressString {
            return s
        }

        if syncRateLimited { return "Pausing" }
        if syncTransitioning { return syncSwitchedOn ? "Deactivating" : "Activating" }

        let i = -lastSyncCompletion.timeIntervalSinceNow
        if i < 1.0 {
            return "Synced"
        } else if lastSyncCompletion != .distantPast, let s = agoFormatter.string(from: i) {
            return "Synced \(s) ago"
        } else {
            return "Never"
        }
    }

    private static func activate() async throws {
        if syncSwitchedOn {
            return
        }

        syncTransitioning = true
        defer {
            syncTransitioning = false
        }

        switch try await container.accountStatus() {
        case .available:
            log("User has iCloud, can activate cloud sync")
            do {
                try await updateSubscriptions()
                try await fetchInitialUUIDSequence()
            } catch {
                log("Error while activating: \(error.finalDescription)")
                try? await deactivate(force: true)
                throw error
            }

        case .couldNotDetermine:
            throw GladysError.cloudAccountRetirevalFailed.error

        case .noAccount:
            throw GladysError.cloudLoginRequired.error

        case .restricted:
            throw GladysError.cloudAccessRestricted.error

        case .temporarilyUnavailable:
            throw GladysError.cloudAccessTemporarilyUnavailable.error

        @unknown default:
            throw GladysError.cloudAccessNotSupported.error
        }
    }

    private static func shutdownShares(ids: [CKRecord.ID], force: Bool, completion: @escaping (Error?) -> Void) {
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
        modifyOperation.savePolicy = .allKeys
        modifyOperation.perRecordCompletionBlock = { record, _ in
            let recordUUID = record.recordID.recordName
            Task { @MainActor in
                if let item = Model.item(shareId: recordUUID) {
                    item.cloudKitShareRecord = nil
                    log("Shut down sharing for item \(item.uuid) before deactivation")
                    item.postModified()
                }
            }
        }
        modifyOperation.modifyRecordsCompletionBlock = { _, _, error in
            Task { @MainActor in
                if !force, let error {
                    completion(error)
                    log("Cloud sync deactivation failed, could not deactivate current shares")
                    syncTransitioning = false
                } else {
                    do {
                        try await deactivate(force: force, deactivatingShares: false)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            }
        }
        submit(modifyOperation, on: container.privateCloudDatabase, type: "shutdown shares")
    }

    static func deactivate(force: Bool, deactivatingShares _: Bool = true) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _deactivate(force: force) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func _deactivate(force: Bool, deactivatingShares: Bool = true, completion: @escaping (Error?) -> Void) {
        syncTransitioning = true

        if deactivatingShares {
            let myOwnShareIds = Model.itemsIAmSharing.compactMap { $0.cloudKitShareRecord?.recordID }
            if !myOwnShareIds.isEmpty {
                shutdownShares(ids: myOwnShareIds, force: force, completion: completion)
                return
            }
        }

        var finalError: Error?

        let ss = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [sharedDatabaseSubscriptionId])
        ss.modifySubscriptionsCompletionBlock = { _, _, error in
            if let error {
                finalError = error
            }
        }
        submit(ss, on: container.sharedCloudDatabase, type: "delete subscription")

        let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [privateDatabaseSubscriptionId])
        ms.modifySubscriptionsCompletionBlock = { _, _, error in
            if let error {
                finalError = error
            }
        }
        submit(ms, on: container.privateCloudDatabase, type: "delete subscription")

        let doneOperation = BlockOperation {
            if let finalError, !force {
                log("Cloud sync deactivation failed")
                completion(finalError)
            } else {
                deletionQueue.removeAll()
                lastSyncCompletion = .distantPast
                uuidSequence = []
                uuidSequenceRecord = nil
                PullState.wipeDatabaseTokens()
                PullState.wipeZoneTokens()
                Model.removeImportedShares()
                syncSwitchedOn = false
                lastiCloudAccount = nil
                PersistedOptions.lastPushToken = nil
                for item in Model.allDrops {
                    item.removeFromCloudkit()
                }
                Model.save()
                log("Cloud sync deactivation complete")
                completion(nil)
            }
            syncTransitioning = false
        }
        doneOperation.addDependency(ss)
        doneOperation.addDependency(ms)
        OperationQueue.main.addOperation(doneOperation)
    }

    private static func proceedWithActivationNow() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let zone = CKRecordZone(zoneID: privateZoneId)
            let createZone = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            createZone.modifyRecordZonesCompletionBlock = { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            submit(createZone, on: container.privateCloudDatabase, type: "create private zone: \(privateZoneId)")
        }
    }

    private static func updateSubscriptions() async throws {
        log("Updating subscriptions to CK zones")
        
        func subscribeToDatabaseOperation(id: String) -> CKModifySubscriptionsOperation {
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            notificationInfo.shouldSendMutableContent = false
            notificationInfo.shouldBadge = false

            let subscription = CKDatabaseSubscription(subscriptionID: id)
            subscription.notificationInfo = notificationInfo
            return CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        }

        let group = DispatchGroup()
        var finalError: Error?

        group.enter()
        let subscribeToPrivateDatabase = subscribeToDatabaseOperation(id: privateDatabaseSubscriptionId)
        subscribeToPrivateDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
            if error != nil {
                finalError = error
            }
            group.leave()
        }
        submit(subscribeToPrivateDatabase, on: container.privateCloudDatabase, type: "subscribe to db")

        group.enter()
        let subscribeToSharedDatabase = subscribeToDatabaseOperation(id: sharedDatabaseSubscriptionId)
        subscribeToSharedDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
            if error != nil {
                finalError = error
            }
            group.leave()
        }
        submit(subscribeToSharedDatabase, on: container.sharedCloudDatabase, type: "subscribe to db")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.notify(queue: .main) {
                if let finalError {
                    continuation.resume(throwing: finalError)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func fetchInitialUUIDSequence() async throws {
        let zone = CKRecordZone(zoneID: privateZoneId)
        let positionListId = CKRecord.ID(recordName: RecordType.positionList.rawValue, zoneID: zone.zoneID)
        let fetchInitialUUIDSequence = CKFetchRecordsOperation(recordIDs: [positionListId])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            fetchInitialUUIDSequence.fetchRecordsCompletionBlock = { ids2records, error in
                if let error, (error as? CKError)?.code != CKError.partialFailure {
                    continuation.resume(throwing: error)
                    return
                }
                if let sequenceRecord = ids2records?[positionListId],
                   let sequence = sequenceRecord["positionList"] as? [String] {
                    log("Received initial record sequence")
                    uuidSequence = sequence
                    uuidSequenceRecord = sequenceRecord
                } else {
                    log("No initial record sequence on server")
                    uuidSequence = []
                }
                syncSwitchedOn = true
                lastiCloudAccount = FileManager.default.ubiquityIdentityToken
                continuation.resume()
            }
            submit(fetchInitialUUIDSequence, on: container.privateCloudDatabase, type: "fetch initial uuid sequence")
        }
    }

    static func eraseZoneIfNeeded(completion: @escaping (Error?) -> Void) {
        showNetwork = true
        let deleteZone = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [privateZoneId])
        deleteZone.modifyRecordZonesCompletionBlock = { _, _, error in
            if let error {
                log("Error while deleting zone: \(error.finalDescription)")
            }
            Task { @MainActor in
                showNetwork = false
                completion(error)
            }
        }
        submit(deleteZone, on: container.privateCloudDatabase, type: "erase private zone")
    }

    static func fetchMissingShareRecords() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _fetchMissingShareRecords { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func _fetchMissingShareRecords(completion: @escaping (Error?) -> Void) {
        var fetchGroups = [CKRecordZone.ID: [CKRecord.ID]]()

        for item in Model.allDrops {
            if let shareId = item.cloudKitRecord?.share?.recordID, item.cloudKitShareRecord == nil {
                let zoneId = shareId.zoneID
                if var existingFetchGroup = fetchGroups[zoneId] {
                    existingFetchGroup.append(shareId)
                    fetchGroups[zoneId] = existingFetchGroup
                } else {
                    fetchGroups[zoneId] = [shareId]
                }
            }
        }

        if fetchGroups.isEmpty {
            completion(nil)
            return
        }

        var finalError: Error?

        let doneOperation = BlockOperation {
            if let finalError {
                log("Error fetching missing share records: \(finalError.finalDescription)")
            }
            completion(finalError)
        }

        for zoneId in fetchGroups.keys {
            guard let fetchGroup = fetchGroups[zoneId] else { continue }
            let fetch = CKFetchRecordsOperation(recordIDs: fetchGroup)
            fetch.perRecordCompletionBlock = { record, recordID, error in
                Task { @MainActor in
                    if let error {
                        if error.itemDoesNotExistOnServer, let recordID {
                            // this share record does not exist. Our local data is wrong
                            if let itemWithShare = Model.item(shareId: recordID.recordName) {
                                log("Warning: Our local data thinks we have a share in the cloud (\(recordID.recordName) for item (\(itemWithShare.uuid.uuidString), but no such record exists. Trying a rescue of the remote record.")
                                fetchCloudRecord(for: itemWithShare, completion: nil)
                            }
                        } else {
                            finalError = error
                        }
                    }
                    if let share = record as? CKShare, let existingItem = Model.item(shareId: share.recordID.recordName) {
                        existingItem.cloudKitShareRecord = share
                    }
                }
            }
            doneOperation.addDependency(fetch)
            let database = zoneId == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
            submit(fetch, on: database, type: "fetch missing share records for items")
        }

        OperationQueue.main.addOperation(doneOperation)
    }

    private static func fetchCloudRecord(for item: ArchivedItem?, completion: ((Error?) -> Void)?) {
        guard let itemNeedingCloudPull = item, let recordIdNeedingRefresh = itemNeedingCloudPull.cloudKitRecord?.recordID else { return }
        let fetch = CKFetchRecordsOperation(recordIDs: [recordIdNeedingRefresh])
        fetch.perRecordCompletionBlock = { record, _, error in
            if let record {
                Task { @MainActor in
                    log("Replaced local cloud record with latest copy from server (\(itemNeedingCloudPull.uuid))")
                    itemNeedingCloudPull.cloudKitRecord = record
                    itemNeedingCloudPull.postModified()
                }
            } else if let error, error.itemDoesNotExistOnServer {
                Task { @MainActor in
                    log("Determined no cloud record exists for item, clearing local related cloud records so next sync can re-create them (\(itemNeedingCloudPull.uuid))")
                    itemNeedingCloudPull.removeFromCloudkit()
                    itemNeedingCloudPull.postModified()
                }
            }
            Task { @MainActor in
                completion?(error)
            }
        }
        let database = recordIdNeedingRefresh.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
        submit(fetch, on: database, type: "fetching individual cloud record")
    }

    static func sync(scope: CKDatabase.Scope? = nil, force: Bool = false, overridingUserPreference: Bool = false) async throws {
        if let l = lastiCloudAccount {
            let newToken = FileManager.default.ubiquityIdentityToken
            if !l.isEqual(newToken) {
                // shutdown
                if newToken == nil {
                    await genericAlert(title: "Sync Failure", message: "You are not logged into iCloud anymore, so sync was disabled.")
                } else {
                    await genericAlert(title: "Sync Failure", message: "You have changed iCloud accounts. iCloud sync was disabled to keep your data safe. You can re-activate it to upload all your data to this account as well.")
                }
                try? await deactivate(force: true)
                return
            }
        }

        do {
            try await attemptSync(scope: scope, force: force, overridingUserPreference: overridingUserPreference)
        } catch {
            if let ckError = error as? CKError {
                try await reactToCkError(ckError, force: force, overridingUserPreference: overridingUserPreference)
            } else {
                throw error
            }
        }
    }

    private static func reactToCkError(_ ckError: CKError, force: Bool, overridingUserPreference: Bool) async throws {
        switch ckError.code {
        case .accountTemporarilyUnavailable:
            log("iCloud account temporarily unavailable")
            fallthrough

        case .assetNotAvailable, .badContainer, .badDatabase, .incompatibleVersion, .managedAccountRestricted, .missingEntitlement,
             .notAuthenticated, .userDeletedZone, .zoneNotFound:

            // shutdown-worthy failure
            await genericAlert(title: "Sync Failure", message: "There was an irrecoverable failure in sync and it was disabled:\n\n\"\(ckError.finalDescription)\"")
            try? await deactivate(force: true)

        case .assetFileModified, .changeTokenExpired, .requestRateLimited, .serverResponseLost, .serviceUnavailable, .zoneBusy:

            // retry
            let timeToRetry = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 6.0
            syncRateLimited = true
            try? await Task.sleep(nanoseconds: UInt64(timeToRetry * Double(NSEC_PER_SEC)))
            syncRateLimited = false
            try await attemptSync(scope: nil, force: force, overridingUserPreference: overridingUserPreference)

        case .alreadyShared, .assetFileNotFound, .batchRequestFailed, .constraintViolation, .internalError, .invalidArguments, .limitExceeded, .networkFailure,
             .networkUnavailable, .operationCancelled, .partialFailure, .participantMayNeedVerification, .permissionFailure, .quotaExceeded,
             .referenceViolation, .resultsTruncated, .serverRecordChanged, .serverRejectedRequest, .tooManyParticipants, .unknownItem:

            // regular failure
            throw ckError

        @unknown default:
            // not handled, let's assume it's important
            throw ckError
        }
    }

    static func share(item: ArchivedItem, rootRecord: CKRecord, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
        let shareRecord = CKShare(rootRecord: rootRecord)
        shareRecord[CKShare.SystemFieldKey.title] = item.trimmedSuggestedName as NSString
        let icon = item.displayIcon
        let scaledIcon = icon.limited(to: Component.iconPointSize, limitTo: 1, useScreenScale: false, singleScale: true)
        #if os(iOS)
            shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.pngData() as NSData?
        #else
            shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.tiffRepresentation as NSData?
        #endif
        let componentsThatNeedMigrating = item.components.filter { $0.cloudKitRecord?.parent == nil }.compactMap(\.populatedCloudKitRecord)
        let recordsToSave = [rootRecord, shareRecord] + componentsThatNeedMigrating
        let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: [])
        operation.savePolicy = .allKeys
        operation.modifyRecordsCompletionBlock = { _, _, error in
            completion(shareRecord, container, error)
        }
        submit(operation, on: container.privateCloudDatabase, type: "share item")
    }

    static func acceptShare(_ metadata: CKShare.Metadata) {
        if !syncSwitchedOn {
            Task {
                await genericAlert(title: "Could not accept shared item",
                                   message: "You need to enable iCloud sync from preferences before accepting items shared in iCloud")
            }
            return
        }
        if let existingItem = Model.item(uuid: metadata.rootRecordID.recordName) {
            let request = HighlightRequest(uuid: existingItem.uuid.uuidString, extraAction: .none)
            sendNotification(name: .HighlightItemRequested, object: request)
            return
        }
        sendNotification(name: .AcceptStarting, object: nil)
        Task {
            try? await sync() // make sure all our previous deletions related to shares are caught up in the change tokens, just in case
            showNetwork = true
            let acceptShareOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            acceptShareOperation.acceptSharesCompletionBlock = { error in
                Task { @MainActor in
                    showNetwork = false
                    if let error {
                        sendNotification(name: .AcceptEnding, object: nil)
                        await genericAlert(title: "Could not accept shared item", message: error.finalDescription)
                    } else {
                        try? await sync()
                        sendNotification(name: .AcceptEnding, object: nil)
                    }
                }
            }
            acceptShareOperation.qualityOfService = .userInitiated
            CKContainer(identifier: metadata.containerIdentifier).add(acceptShareOperation)
        }
    }

    static func deleteShare(_ item: ArchivedItem, completion: @escaping (Error?) -> Void) {
        guard let shareId = item.cloudKitRecord?.share?.recordID ?? item.cloudKitShareRecord?.recordID else {
            completion(nil)
            return
        }
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [shareId])
        deleteOperation.modifyRecordsCompletionBlock = { _, _, error in
            Task { @MainActor in
                if let error, !error.itemDoesNotExistOnServer {
                    await genericAlert(title: "There was an error while un-sharing this item", message: error.finalDescription)
                    completion(error)
                } else { // our local record must be stale, let's refresh it just in case
                    item.cloudKitShareRecord = nil
                    fetchCloudRecord(for: item, completion: completion)
                }
            }
        }
        let database = shareId.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
        submit(deleteOperation, on: database, type: "delete share")
    }

    static func proceedWithDeactivation() async {
        do {
            try await deactivate(force: false)
        } catch {
            await genericAlert(title: "Could not deactivate", message: error.finalDescription)
        }
    }

    static func startActivation() async {
        do {
            try await activate()
        } catch {
            await genericAlert(title: "Could not activate", message: error.finalDescription, offerSettingsShortcut: (error as NSError).code == GladysError.cloudLoginRequired.rawValue)
        }
        do {
            try await sync(force: true, overridingUserPreference: true)
        } catch {
            await genericAlert(title: "Initial sync failed", message: error.finalDescription)
        }
    }

    private static func attemptSync(scope: CKDatabase.Scope?, force: Bool, overridingUserPreference: Bool) async throws {
        if !syncSwitchedOn {
            return
        }

        #if os(iOS)
            if !force, !overridingUserPreference {
                if syncContextSetting == .wifiOnly, reachability.status != .reachableViaWiFi {
                    log("Skipping auto sync because no WiFi is present and user has selected WiFi sync only")
                    return
                }
                if syncContextSetting == .manualOnly {
                    log("Skipping auto sync because user selected manual sync only")
                    return
                }
            }
        #endif

        if syncing, !force {
            log("Sync already running, but need another one. Marked to retry at the end of this.")
            syncDirty = true
            return
        }

        #if os(iOS)
            BackgroundTask.registerForBackground()
            defer {
                BackgroundTask.unregisterForBackground()
            }
        #endif

        syncing = true
        syncDirty = false

        do {
            try await sendUpdatesUp()
            try await PullState().fetchDatabaseChanges(scope: scope)
            if syncDirty {
                try await attemptSync(scope: nil, force: true, overridingUserPreference: overridingUserPreference)
            } else {
                lastSyncCompletion = Date()
                syncing = false
            }
        } catch {
            log("Sync failure: \(error.finalDescription)")
            syncing = false
            throw error
        }
    }

    static func apnsUpdate(_ newToken: Data?) {
        guard let newToken else {
            log("Warning: APNS registration failed")
            return
        }

        if newToken == PersistedOptions.lastPushToken, PersistedOptions.migratedSubscriptions8 {
            log("APNS ready: \(newToken.base64EncodedString())")
            return
        }

        log("APNS ready: \(newToken.base64EncodedString())")

        if !PersistedOptions.migratedSubscriptions8 {
            PersistedOptions.migratedSubscriptions8 = true
            PersistedOptions.lastPushToken = nil
            log("Push migration needed - existing push token reset")
        }
        
        guard syncSwitchedOn else {
            PersistedOptions.lastPushToken = newToken
            return
        }

        log("Will subscribe for CK notifications")

        Task {
            do {
                try await updateSubscriptions()
                log("Subscriptions updated successfully, storing new APNS token")
                PersistedOptions.lastPushToken = newToken
            } catch {
                log("Subscription update failed: \(error.localizedDescription)")
            }
        }
    }
}
