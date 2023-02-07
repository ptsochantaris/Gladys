#if os(macOS)
    import Cocoa
#else
    import UIKit
#endif
import CloudKit
import GladysCommon

extension CloudManager {
    static let privateDatabaseSubscriptionId = "private-changes"
    static let sharedDatabaseSubscriptionId = "shared-changes"

    nonisolated static func submit(_ operation: CKDatabaseOperation, on database: CKDatabase, type: String) {
        log("CK \(database.databaseScope.logName) database, operation \(operation.operationID): \(type)")
        operation.qualityOfService = .userInitiated
        database.add(operation)
    }

    public static var showNetwork = false {
        didSet {
            Task {
                await Model.updateBadge()
            }
        }
    }

    public static var syncProgressString: String?

    private static let syncProgressDebouncer = PopTimer(timeInterval: 0.2) {
        #if DEBUG
            if let s = syncProgressString {
                log(">>> Sync label updated: \(s)")
            } else {
                log(">>> Sync label cleared")
            }
        #endif
        Task { @MainActor in
            sendNotification(name: .CloudManagerStatusChanged, object: nil)
        }
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
        for item in await DropStore.allDrops where item.needsCloudPush {
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

        var sharedPushStates = ContiguousArray<PushState>()
        sharedPushStates.reserveCapacity(sharedZonesToPush.count)
        for sharedZoneId in sharedZonesToPush {
            let pushState = await PushState(zoneId: sharedZoneId, database: container.sharedCloudDatabase)
            sharedPushStates.append(pushState)
        }

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

    public static var syncTransitioning = false {
        didSet {
            if syncTransitioning != oldValue {
                showNetwork = syncing || syncTransitioning
                Task {
                    await sendNotification(name: .CloudManagerStatusChanged, object: nil)
                }
            }
        }
    }

    public static var syncRateLimited = false {
        didSet {
            if syncTransitioning != oldValue {
                setSyncProgressString(syncing ? "Pausing" : nil)
                showNetwork = false
                Task {
                    await sendNotification(name: .CloudManagerStatusChanged, object: nil)
                }
            }
        }
    }

    public static var syncing = false {
        didSet {
            if syncing != oldValue {
                setSyncProgressString(syncing ? "Syncing" : nil)
                showNetwork = syncing || syncTransitioning
                Task {
                    await sendNotification(name: .CloudManagerStatusChanged, object: nil)
                }
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
    public static var lastSyncCompletion: Date

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
        appStorageUrl.appendingPathComponent("ck-uuid-sequence", isDirectory: false)
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
        appStorageUrl.appendingPathComponent("ck-delete-queue", isDirectory: false)
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

    public static func markAsDeleted(recordName: String, cloudKitRecord: CKRecord?) {
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

    @MainActor
    private static let agoFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    public static func makeSyncString() async -> String {
        if let s = syncProgressString {
            return s
        }

        if syncRateLimited { return "Pausing" }
        if syncTransitioning { return syncSwitchedOn ? "Deactivating" : "Activating" }
        if syncing { return "Syncing" }

        let last = lastSyncCompletion
        let i = -last.timeIntervalSinceNow
        if i < 1.0 {
            return "Synced"
        } else if last != .distantPast, let s = agoFormatter.string(from: i) {
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
                let zone = CKRecordZone(zoneID: privateZoneId)
                let modifyResults = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
                try check(modifyResults)
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

    private static func shutdownShares(ids: [CKRecord.ID], force: Bool) async throws {
        do {
            let modifyResult = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys)
            for recordID in modifyResult.deleteResults.keys {
                let recordUUID = recordID.recordName
                if let item = await DropStore.item(shareId: recordUUID) {
                    item.cloudKitShareRecord = nil
                    log("Shut down sharing for item \(item.uuid) before deactivation")
                    item.postModified()
                }
            }
        } catch {
            if force { return }
            log("Cloud sync deactivation failed, could not deactivate current shares")
            syncTransitioning = false
            throw error
        }
    }

    static func deactivate(force: Bool) async throws {
        syncTransitioning = true
        defer {
            syncTransitioning = false
        }

        let myOwnShareIds = await DropStore.itemsIAmSharing.compactMap { $0.cloudKitShareRecord?.recordID }
        if !myOwnShareIds.isEmpty {
            try await shutdownShares(ids: myOwnShareIds, force: force)
        }

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                _ = try await container.sharedCloudDatabase.deleteSubscription(withID: sharedDatabaseSubscriptionId)
            }
            taskGroup.addTask {
                _ = try await container.privateCloudDatabase.deleteSubscription(withID: privateDatabaseSubscriptionId)
            }
            do {
                try await taskGroup.waitForAll()
            } catch {
                log("Cloud sync deactivation failed: \(error.finalDescription)")
                throw error
            }
        }

        deletionQueue.removeAll()
        lastSyncCompletion = .distantPast
        uuidSequence = []
        uuidSequenceRecord = nil
        PullState.wipeDatabaseTokens()
        PullState.wipeZoneTokens()
        await Model.removeImportedShares()
        syncSwitchedOn = false
        lastiCloudAccount = nil
        PersistedOptions.lastPushToken = nil
        for item in await DropStore.allDrops {
            item.removeFromCloudkit()
        }
        await Model.save()
        log("Cloud sync deactivation complete")
    }

    private static func subscriptionToDatabaseZone(id: String) -> CKDatabaseSubscription {
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.shouldSendMutableContent = false
        notificationInfo.shouldBadge = false

        let subscription = CKDatabaseSubscription(subscriptionID: id)
        subscription.notificationInfo = notificationInfo
        return subscription
    }

    private static func updateSubscriptions() async throws {
        log("Updating subscriptions to CK zones")

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                let subscribeToPrivateDatabase = await subscriptionToDatabaseZone(id: privateDatabaseSubscriptionId)
                _ = try await container.privateCloudDatabase.modifySubscriptions(saving: [subscribeToPrivateDatabase], deleting: [])
            }
            taskGroup.addTask {
                let subscribeToSharedDatabase = await subscriptionToDatabaseZone(id: sharedDatabaseSubscriptionId)
                _ = try await container.sharedCloudDatabase.modifySubscriptions(saving: [subscribeToSharedDatabase], deleting: [])
            }
            do {
                try await taskGroup.waitForAll()
            } catch {
                log("CK zone subscription failed: \(error.finalDescription)")
                throw error
            }
        }
    }

    private static func fetchInitialUUIDSequence() async throws {
        let zone = CKRecordZone(zoneID: privateZoneId)
        let positionListId = CKRecord.ID(recordName: RecordType.positionList.rawValue, zoneID: zone.zoneID)

        let sequenceRecord: CKRecord?
        do {
            sequenceRecord = try await container.privateCloudDatabase.record(for: positionListId)
        } catch {
            if error.itemDoesNotExistOnServer {
                sequenceRecord = nil
            } else {
                throw error
            }
        }

        if let sequence = sequenceRecord?["positionList"] as? [String] {
            log("Received initial record sequence")
            uuidSequence = sequence
        } else {
            log("No initial record sequence on server")
            uuidSequence = []
        }
        uuidSequenceRecord = sequenceRecord
        syncSwitchedOn = true
        lastiCloudAccount = FileManager.default.ubiquityIdentityToken
    }

    public static func eraseZoneIfNeeded() async throws {
        showNetwork = true
        defer {
            showNetwork = false
        }
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: privateZoneId)
        } catch {
            log("Error while deleting zone: \(error.finalDescription)")
            throw error
        }
    }

    static func fetchMissingShareRecords() async throws {
        var fetchGroups = [CKRecordZone.ID: LinkedList<CKRecord.ID>]()

        for item in await DropStore.allDrops {
            if let shareId = item.cloudKitRecord?.share?.recordID, item.cloudKitShareRecord == nil {
                let zoneId = shareId.zoneID
                if let existingFetchGroup = fetchGroups[zoneId] {
                    existingFetchGroup.append(shareId)
                } else {
                    fetchGroups[zoneId] = LinkedList(value: shareId)
                }
            }
        }

        if fetchGroups.isEmpty {
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for (zoneId, fetchGroup) in fetchGroups {
                taskGroup.addTask { @MainActor in
                    let c = await container
                    let database = zoneId == privateZoneId ? c.privateCloudDatabase : c.sharedCloudDatabase
                    let fetchResults = try await database.records(for: Array(fetchGroup))
                    for (id, result) in fetchResults {
                        switch result {
                        case let .success(record):
                            if let share = record as? CKShare, let existingItem = DropStore.item(shareId: share.recordID.recordName) {
                                existingItem.cloudKitShareRecord = share
                            }
                        case let .failure(error):
                            if error.itemDoesNotExistOnServer {
                                // this share record does not exist. Our local data is wrong
                                if let itemWithShare = DropStore.item(shareId: id.recordName) {
                                    log("Warning: Our local data thinks we have a share in the cloud (\(id.recordName) for item (\(itemWithShare.uuid.uuidString), but no such record exists. Trying a rescue of the remote record.")
                                    try? await fetchCloudRecord(for: itemWithShare)
                                }
                            } else {
                                log("Error fetching missing share records: \(error.finalDescription)")
                                throw error
                            }
                        }
                    }
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private static func fetchCloudRecord(for item: ArchivedItem?) async throws {
        guard let item, let recordIdNeedingRefresh = item.cloudKitRecord?.recordID else { return }

        let database = recordIdNeedingRefresh.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
        do {
            let record = try await database.record(for: recordIdNeedingRefresh)
            log("Replaced local cloud record with latest copy from server (\(item.uuid))")
            item.cloudKitRecord = record
            item.postModified()

        } catch {
            if error.itemDoesNotExistOnServer {
                log("Determined no cloud record exists for item, clearing local related cloud records so next sync can re-create them (\(item.uuid))")
                item.removeFromCloudkit()
                item.postModified()
            }
        }
    }

    public static func sync(scope: CKDatabase.Scope? = nil, force: Bool = false, overridingUserPreference: Bool = false) async throws {
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

    public static func share(item: ArchivedItem, rootRecord: CKRecord) async throws -> CKShare {
        let shareRecord = CKShare(rootRecord: rootRecord)
        shareRecord[CKShare.SystemFieldKey.title] = item.trimmedSuggestedName as NSString
        let scaledIcon = item.displayIcon.limited(to: Component.iconPointSize, limitTo: 1, useScreenScale: false, singleScale: true)
        #if os(macOS)
            shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.tiffRepresentation as NSData?
        #else
            shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.pngData() as NSData?
        #endif
        let componentsThatNeedMigrating = item.components.filter { $0.cloudKitRecord?.parent == nil }.compactMap(\.populatedCloudKitRecord)
        let recordsToSave = [rootRecord, shareRecord] + componentsThatNeedMigrating
        let modifyResults = try await container.privateCloudDatabase.modifyRecords(saving: recordsToSave, deleting: [], savePolicy: .allKeys)
        try check(modifyResults)
        return shareRecord
    }

    public static func acceptShare(_ metadata: CKShare.Metadata) async {
        guard syncSwitchedOn else {
            await genericAlert(title: "Could not accept shared item",
                               message: "You need to enable iCloud sync from preferences before accepting items shared in iCloud")
            return
        }

        if let existingItem = await DropStore.item(uuid: metadata.rootRecordID.recordName) {
            let request = HighlightRequest(uuid: existingItem.uuid.uuidString, extraAction: .none)
            await sendNotification(name: .HighlightItemRequested, object: request)
            return
        }

        await sendNotification(name: .AcceptStarting, object: nil)

        try? await sync() // make sure all our previous deletions related to shares are caught up in the change tokens, just in case
        showNetwork = true
        do {
            try await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)
            try? await sync() // get the new shared objects
            await sendNotification(name: .AcceptEnding, object: nil)
            showNetwork = false
        } catch {
            await sendNotification(name: .AcceptEnding, object: nil)
            showNetwork = false
            await genericAlert(title: "Could not accept shared item", message: error.finalDescription)
        }
    }

    public static func deleteShare(_ item: ArchivedItem) async throws {
        guard let shareId = item.cloudKitRecord?.share?.recordID ?? item.cloudKitShareRecord?.recordID else {
            return
        }

        do {
            let database = shareId.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
            _ = try await database.deleteRecord(withID: shareId)
        } catch {
            if error.itemDoesNotExistOnServer {
                do {
                    item.cloudKitShareRecord = nil
                    try await fetchCloudRecord(for: item)
                } catch {
                    throw error
                }
            } else {
                await genericAlert(title: "There was an error while un-sharing this item", message: error.finalDescription)
                throw error
            }
        }
    }

    public static func proceedWithDeactivation() async {
        do {
            try await deactivate(force: false)
        } catch {
            await genericAlert(title: "Could not deactivate", message: error.finalDescription)
        }
    }

    public static func startActivation() async {
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

    public static var shouldSyncAttempProceed: ((Bool, Bool) async -> Bool)?
    public static var syncAttempDone: (() async -> Void)?
    private static let requestGateKeeper = GateKeeper(entries: 1)

    private static func attemptSync(scope: CKDatabase.Scope?, force: Bool, overridingUserPreference: Bool) async throws {
        await requestGateKeeper.waitForGate()
        await BackgroundTask.registerForBackground()
        defer {
            requestGateKeeper.signalGate()
            Task {
                await BackgroundTask.unregisterForBackground()
            }
        }
        
        if !syncSwitchedOn {
            return
        }
                
        if let shouldSyncAttempProceed, await shouldSyncAttempProceed(force, overridingUserPreference) == false {
            return
        }
        
        defer {
            Task {
                await syncAttempDone?()
            }
        }
        
        syncing = true
        
        do {
            try await sendUpdatesUp()
            try await PullState().fetchDatabaseChanges(scope: scope)
            lastSyncCompletion = Date()
            syncing = false

        } catch {
            log("Sync failure: \(error.finalDescription)")
            syncing = false
            throw error
        }
    }

    public static func apnsUpdate(_ newToken: Data?) {
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
