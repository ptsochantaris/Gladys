#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
import CloudKit
import GladysCommon
import Lista
import Maintini
import PopTimer
import Semalot

public extension CloudManager {
    internal static let privateDatabaseSubscriptionId = "private-changes"
    internal static let sharedDatabaseSubscriptionId = "shared-changes"

    static var showNetwork = false {
        didSet {
            Task {
                await Model.updateBadge()
            }
        }
    }

    static var syncProgressString: String?

    private static let syncProgressDebouncer = PopTimer(timeInterval: 0.1) {
        #if DEBUG
            if let syncProgressString {
                log(">>> Sync label updated: \(syncProgressString)")
            } else {
                log(">>> Sync label cleared")
            }
        #endif
        sendNotification(name: .CloudManagerStatusChanged)
    }

    internal static func setSyncProgressString(_ newString: String?) {
        syncProgressString = newString
        syncProgressDebouncer.push()
    }

    private static func sendUpdatesUp() async throws {
        if !syncSwitchedOn {
            return
        }

        var sharedZonesToPush = Set<CKRecordZone.ID>()
        for item in await DropStore.allDrops where await item.needsCloudPush {
            let zoneID = await item.parentZone
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

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask {
                let pushState = await PushState(zoneId: privateZoneId, database: container.privateCloudDatabase)
                try await pushState.perform()
            }
            for sharedZoneId in sharedZonesToPush {
                group.addTask {
                    let pushState = await PushState(zoneId: sharedZoneId, database: container.sharedCloudDatabase)
                    try await pushState.perform()
                }
            }
        }
    }

    static var syncTransitioning = false {
        didSet {
            if syncTransitioning != oldValue {
                showNetwork = syncing || syncTransitioning
                sendNotification(name: .CloudManagerStatusChanged)
            }
        }
    }

    static var syncRateLimited = false {
        didSet {
            if syncTransitioning != oldValue {
                setSyncProgressString(syncing ? "Pausing" : nil)
                showNetwork = false
                sendNotification(name: .CloudManagerStatusChanged)
            }
        }
    }

    static var syncing = false {
        didSet {
            if syncing != oldValue {
                setSyncProgressString(syncing ? "Syncing" : nil)
                showNetwork = syncing || syncTransitioning
                sendNotification(name: .CloudManagerStatusChanged)
            }
        }
    }

    internal typealias ICloudToken = (NSCoding & NSCopying & NSObjectProtocol)
    internal static var lastiCloudAccount: ICloudToken? {
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

    internal static var uuidSequence: [String] {
        get {
            if let data = PersistedOptions.defaults.data(forKey: "uuidSequence") {
                SafeArchiving.unarchive(data) as? [String] ?? []
            } else {
                []
            }
        }
        set {
            if let data = SafeArchiving.archive(newValue) {
                PersistedOptions.defaults.set(data, forKey: "uuidSequence")
            }
        }
    }

    internal static var uuidSequenceRecordPath: URL {
        appStorageUrl.appendingPathComponent("ck-uuid-sequence", isDirectory: false)
    }

    internal static var uuidSequenceRecord: CKRecord? {
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

    internal static var deleteQueuePath: URL {
        appStorageUrl.appendingPathComponent("ck-delete-queue", isDirectory: false)
    }

    internal static var deletionQueue: Set<String> {
        get {
            if let data = try? Data(contentsOf: deleteQueuePath) {
                SafeArchiving.unarchive(data) as? Set<String> ?? []
            } else {
                []
            }
        }
        set {
            try? SafeArchiving.archive(newValue)?.write(to: deleteQueuePath)
        }
    }

    private static func deletionTag(for recordName: String, cloudKitRecord: CKRecord?) -> String {
        if let zoneId = cloudKitRecord?.recordID.zoneID {
            zoneId.zoneName + ":" + zoneId.ownerName + ":" + recordName
        } else {
            recordName
        }
    }

    static func markAsDeleted(recordName: String, cloudKitRecord: CKRecord?) {
        if syncSwitchedOn {
            deletionQueue.insert(deletionTag(for: recordName, cloudKitRecord: cloudKitRecord))
        }
    }

    internal static func commitDeletion(for recordNames: [String]) {
        if recordNames.isEmpty { return }

        CloudManager.deletionQueue = CloudManager.deletionQueue.filter {
            if let lastPartOfTag = $0.components(separatedBy: ":").last {
                !recordNames.contains(lastPartOfTag)
            } else {
                true
            }
        }
    }

    static func makeSyncString() async -> String {
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
                log("Error while activating: \(error.localizedDescription)")
                try? await deactivate(force: true)
                throw error
            }

        case .couldNotDetermine:
            throw GladysError.cloudAccountRetirevalFailed

        case .noAccount:
            throw GladysError.cloudLoginRequired

        case .restricted:
            throw GladysError.cloudAccessRestricted

        case .temporarilyUnavailable:
            throw GladysError.cloudAccessTemporarilyUnavailable

        @unknown default:
            throw GladysError.cloudAccessNotSupported
        }
    }

    private static func shutdownShares(ids: [CKRecord.ID], force: Bool) async throws {
        do {
            let modifyResult = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys)
            for recordID in modifyResult.deleteResults.keys {
                let recordUUID = recordID.recordName
                if let item = await DropStore.item(shareId: recordUUID) {
                    await item.setCloudKitShareRecord(nil)
                    log("Shut down sharing for item \(item.uuid) before deactivation")
                    await item.postModified()
                }
            }
        } catch {
            if force { return }
            log("Cloud sync deactivation failed, could not deactivate current shares")
            syncTransitioning = false
            throw error
        }
    }

    internal static func deactivate(force: Bool) async throws {
        syncTransitioning = true
        defer {
            syncTransitioning = false
        }

        var myOwnShareIds = [CKRecord.ID]()
        for record in await DropStore.itemsIAmSharing {
            if let id = await record.cloudKitShareRecord?.recordID {
                myOwnShareIds.append(id)
            }
        }
        if myOwnShareIds.isPopulated {
            try await shutdownShares(ids: myOwnShareIds, force: force)
        }

        do {
            try await withThrowingDiscardingTaskGroup {
                $0.addTask {
                    _ = try await container.sharedCloudDatabase.deleteSubscription(withID: sharedDatabaseSubscriptionId)
                }
                $0.addTask {
                    _ = try await container.privateCloudDatabase.deleteSubscription(withID: privateDatabaseSubscriptionId)
                }
            }
        } catch {
            if force { return }
            log("Cloud sync deactivation failed: \(error.localizedDescription)")
            throw error
        }

        deletionQueue.removeAll()
        lastSyncCompletion = .distantPast
        uuidSequence = []
        uuidSequenceRecord = nil
        await PullState.wipeDatabaseTokens()
        await PullState.wipeZoneTokens()
        await Model.removeImportedShares()
        syncSwitchedOn = false
        lastiCloudAccount = nil
        await MainActor.run {
            PersistedOptions.lastPushToken = nil
        }
        for item in await DropStore.allDrops {
            await item.removeFromCloudkit()
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

        do {
            try await withThrowingDiscardingTaskGroup {
                $0.addTask {
                    let subscribeToPrivateDatabase = await subscriptionToDatabaseZone(id: privateDatabaseSubscriptionId)
                    _ = try await container.privateCloudDatabase.modifySubscriptions(saving: [subscribeToPrivateDatabase], deleting: [])
                }
                $0.addTask {
                    let subscribeToSharedDatabase = await subscriptionToDatabaseZone(id: sharedDatabaseSubscriptionId)
                    _ = try await container.sharedCloudDatabase.modifySubscriptions(saving: [subscribeToSharedDatabase], deleting: [])
                }
            }
        } catch {
            log("CK zone subscription failed: \(error.localizedDescription)")
            throw error
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

    static func eraseZoneIfNeeded() async throws {
        showNetwork = true
        defer {
            showNetwork = false
        }
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: privateZoneId)
        } catch {
            log("Error while deleting zone: \(error.localizedDescription)")
            throw error
        }
    }

    internal static func fetchMissingShareRecords() async throws {
        var fetchGroups = [CKRecordZone.ID: Lista<CKRecord.ID>]()

        for item in await DropStore.allDrops {
            if let shareId = await item.cloudKitRecord?.share?.recordID, await item.cloudKitShareRecord == nil {
                let zoneId = shareId.zoneID
                if let existingFetchGroup = fetchGroups[zoneId] {
                    existingFetchGroup.append(shareId)
                } else {
                    fetchGroups[zoneId] = Lista(value: shareId)
                }
            }
        }

        if fetchGroups.isEmpty {
            return
        }

        try await withThrowingDiscardingTaskGroup { taskGroup in
            for (zoneId, fetchGroup) in fetchGroups {
                let groupArray = Array(fetchGroup)
                taskGroup.addTask {
                    let c = await container
                    let database = zoneId == privateZoneId ? c.privateCloudDatabase : c.sharedCloudDatabase
                    let fetchResults = try await database.records(for: groupArray)
                    for (id, result) in fetchResults {
                        switch result {
                        case let .success(record):
                            if let share = record as? CKShare, let existingItem = await DropStore.item(shareId: share.recordID.recordName) {
                                await MainActor.run {
                                    existingItem.cloudKitShareRecord = share
                                }
                            }
                        case let .failure(error):
                            if error.itemDoesNotExistOnServer {
                                // this share record does not exist. Our local data is wrong
                                if let itemWithShare = await DropStore.item(shareId: id.recordName) {
                                    log("Warning: Our local data thinks we have a share in the cloud (\(id.recordName) for item (\(itemWithShare.uuid.uuidString), but no such record exists. Trying a rescue of the remote record.")
                                    try? await fetchCloudRecord(for: itemWithShare)
                                }
                            } else {
                                log("Error fetching missing share records: \(error.localizedDescription)")
                                throw error
                            }
                        }
                    }
                }
            }
        }
    }

    private static func fetchCloudRecord(for item: ArchivedItem?) async throws {
        guard let item, let recordIdNeedingRefresh = await item.cloudKitRecord?.recordID else { return }

        let database = recordIdNeedingRefresh.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
        do {
            let record = try await database.record(for: recordIdNeedingRefresh)
            log("Replaced local cloud record with latest copy from server (\(item.uuid))")
            await item.setCloudKitRecord(record)
            await item.postModified()

        } catch {
            if error.itemDoesNotExistOnServer {
                log("Determined no cloud record exists for item, clearing local related cloud records so next sync can re-create them (\(item.uuid))")
                await item.removeFromCloudkit()
                await item.postModified()
            }
        }
    }

    static func opportunisticSyncIfNeeded(force: Bool = false) async throws {
        guard syncSwitchedOn, !syncing else {
            return
        }

        if force || lastSyncCompletion.timeIntervalSinceNow < -60 {
            try await sync()
            return
        }

        #if canImport(UIKit)
            if await UIApplication.shared.backgroundRefreshStatus != .available {
                try await sync()
            }
        #endif
    }

    static func sync(scope: CKDatabase.Scope? = nil, force: Bool = false) async throws {
        if let l = lastiCloudAccount {
            let newToken = FileManager.default.ubiquityIdentityToken
            if !l.isEqual(newToken) {
                try? await deactivate(force: true)
                if newToken == nil {
                    throw GladysError.cloudLogoutDetected
                } else {
                    throw GladysError.cloudLoginChanged
                }
            }
        }

        do {
            try await attemptSync(scope: scope, force: force)
        } catch {
            if let ckError = error as? CKError {
                try await reactToCkError(ckError, force: force)
            } else {
                throw error
            }
        }
    }

    private static func reactToCkError(_ ckError: CKError, force: Bool) async throws {
        switch ckError.code {
        case .accountTemporarilyUnavailable:
            log("iCloud account temporarily unavailable")
            fallthrough

        case .assetNotAvailable, .badContainer, .badDatabase, .incompatibleVersion, .managedAccountRestricted, .missingEntitlement,
             .notAuthenticated, .userDeletedZone, .zoneNotFound:

            try? await deactivate(force: true)
            throw GladysError.syncFailure(ckError)

        case .assetFileModified, .changeTokenExpired, .requestRateLimited, .serverResponseLost, .serviceUnavailable, .zoneBusy:

            // retry
            let timeToRetry = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 6.0
            syncRateLimited = true
            try? await Task.sleep(nanoseconds: UInt64(timeToRetry * Double(NSEC_PER_SEC)))
            syncRateLimited = false
            try await attemptSync(scope: nil, force: force)

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

    static func share(item: ArchivedItem, rootRecord: CKRecord) async throws -> CKShare {
        let shareRecord = CKShare(rootRecord: rootRecord)
        shareRecord[CKShare.SystemFieldKey.title] = await item.trimmedSuggestedName as NSString
        let scaledIcon = await item.displayIcon.limited(to: Component.iconPointSize, limitTo: 1, useScreenScale: false, singleScale: true)
        #if canImport(AppKit)
            shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.tiffRepresentation as NSData?
        #else
            shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.pngData() as NSData?
        #endif
        let componentsThatNeedMigrating = await MainActor.run { item.components.filter { $0.cloudKitRecord?.parent == nil }.map(\.populatedCloudKitRecord) }
        let recordsToSave = [rootRecord, shareRecord] + componentsThatNeedMigrating
        let modifyResults = try await container.privateCloudDatabase.modifyRecords(saving: recordsToSave, deleting: [], savePolicy: .allKeys)
        try check(modifyResults)
        return shareRecord
    }

    static func acceptShare(_ metadata: CKShare.Metadata) async throws {
        guard syncSwitchedOn else {
            throw GladysError.acceptRequiresSyncEnabled
        }

        let recordId = metadata.hierarchicalRootRecordID?.recordName
        if let recordId, let existingItem = await DropStore.item(uuid: recordId) {
            HighlightRequest.send(uuid: existingItem.uuid.uuidString, extraAction: .none)
            return
        }

        sendNotification(name: .AcceptStarting)
        try? await sync() // make sure all our previous deletions related to shares are caught up in the change tokens, just in case

        showNetwork = true
        defer {
            sendNotification(name: .AcceptEnding)
            showNetwork = false
        }

        try await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)

        try? await sync() // get the new shared objects
    }

    static func deleteShare(_ itemUuid: UUID) async throws {
        guard let item = await DropStore.item(uuid: itemUuid) else {
            return
        }
        let cloudKitShareId = await item.cloudKitRecord?.share?.recordID
        let shareRecordId = await item.cloudKitShareRecord?.recordID
        guard let shareId = cloudKitShareId ?? shareRecordId else {
            return
        }

        do {
            let database = shareId.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
            _ = try await database.deleteRecord(withID: shareId)
            await item.setCloudKitShareRecord(nil)
            await item.postModified()
        } catch {
            if error.itemDoesNotExistOnServer {
                do {
                    await item.setCloudKitShareRecord(nil)
                    try await fetchCloudRecord(for: item)
                } catch {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    static func proceedWithDeactivation() async throws {
        try await deactivate(force: false)
    }

    static func startActivation() async throws {
        try await activate()
        try await sync(force: true)
    }

    static var shouldSyncAttemptProceed: ((Bool) async -> Bool)?
    private static let requestGateKeeper = Semalot(tickets: 1)

    private static func attemptSync(scope: CKDatabase.Scope?, force: Bool) async throws {
        await requestGateKeeper.takeTicket()
        await Maintini.startMaintaining()
        defer {
            requestGateKeeper.returnTicket()
            Task {
                await Maintini.endMaintaining()
            }
        }

        if !syncSwitchedOn {
            return
        }

        if let shouldSyncAttemptProceed, await shouldSyncAttemptProceed(force) == false {
            return
        }

        syncing = true

        do {
            while await DropStore.ingestingItems == true {
                log("Waiting for ingest to complete before syncing up")
                try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
            }
            try await sendUpdatesUp()
            try await PullState().fetchDatabaseChanges(scope: scope)
            lastSyncCompletion = Date()
            syncing = false

        } catch {
            log("Sync failure: \(error.localizedDescription)")
            syncing = false
            throw error
        }
    }

    @MainActor
    static func apnsUpdate(_ newToken: Data?) async {
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

        guard await syncSwitchedOn else {
            PersistedOptions.lastPushToken = newToken
            return
        }

        log("Will subscribe for CK notifications")

        do {
            try await updateSubscriptions()
            log("Subscriptions updated successfully, storing new APNS token")
            PersistedOptions.lastPushToken = newToken
        } catch {
            log("Subscription update failed: \(error.localizedDescription)")
        }
    }
}
