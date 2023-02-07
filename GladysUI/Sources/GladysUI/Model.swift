import CloudKit
import CoreSpotlight
import Foundation
import GladysCommon
import UniformTypeIdentifiers

public extension UTType {
    static let gladysArchive = UTType(tag: "gladysArchive", tagClass: .filenameExtension, conformingTo: .bundle)!
}

public var brokenMode = false

private var dataFileLastModified = Date.distantPast

@MainActor
public enum Model {
    public enum State {
        case startupComplete, willSave, saveComplete(dueToSyncFetch: Bool), migrated
    }

    public static var badgeHandler: (() -> Void)?
    public static var stateHandler: ((State) -> Void)?

    private static let storageGatekeeper = GateKeeper(entries: 1)

    static func reset() {
        DropStore.reset()
        dataFileLastModified = .distantPast
    }

    public static func reloadDataIfNeeded() async {
        await storageGatekeeper.waitForGate()
        await Task.detached {
            _reloadDataIfNeeded()
        }.value
        storageGatekeeper.signalGate()
    }
    
    private nonisolated static func _reloadDataIfNeeded() {
        if brokenMode {
            log("Ignoring load, model is broken, app needs restart.")
            return
        }

        var coordinationError: NSError?
        var loadingError: NSError?

        // withoutChanges because we only signal the provider after we have saved
        Coordination.coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

            if !FileManager.default.fileExists(atPath: url.path) {
                Task {
                    await DropStore.reset()
                }
                log("Starting fresh store")
                return
            }

            do {
                var shouldLoad = true
                if let dataModified = modificationDate(for: url) {
                    if dataModified == dataFileLastModified {
                        shouldLoad = false
                    } else {
                        dataFileLastModified = dataModified
                    }
                }
                if shouldLoad {
                    log("Needed to reload data, new file date: \(dataFileLastModified)")

                    let start = Date()
                    let result = try dataLoad(from: url)
                    Task {
                        await DropStore.initialize(with: result)
                        await sendNotification(name: .ModelDataUpdated, object: nil)
                    }
                    log("Load time: \(-start.timeIntervalSinceNow) seconds")
                } else {
                    log("No need to reload data")
                }
            } catch {
                log("Loading Error: \(error)")
                loadingError = error as NSError
            }
        }

        if brokenMode {
            log("Model in broken state, further loading or error processing aborted")
            return
        }

        if let loadingError {
            Task {
                await handleLoadingError(loadingError)
            }

        } else if let coordinationError {
            Task {
                await handleCoordinationError(coordinationError)
            }
        }
    }
    
    private nonisolated static func dataLoad(from url: URL) throws -> ContiguousArray<ArchivedItem> {
        let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
        let itemCount = d.count / 16

        let loader = LoaderBuffer(capacity: itemCount)
        d.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            let decoder = loadDecoder
            let uuidSequence = pointer.bindMemory(to: uuid_t.self).prefix(itemCount)
            DispatchQueue.concurrentPerform(iterations: itemCount) { count in
                let us = uuidSequence[count]
                let u = UUID(uuid: us)
                let dataPath = url.appendingPathComponent(u.uuidString)
                if let data = try? Data(contentsOf: dataPath),
                   let item = try? decoder.decode(ArchivedItem.self, from: data) {
                    loader.set(item, at: count)
                }
            }
        }
        return loader.result()
    }

    private static func loadInitialData() {
        var coordinationError: NSError?
        var loadingError: NSError?

        // withoutChanges because we only signal the provider after we have saved
        Coordination.coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

            if !FileManager.default.fileExists(atPath: url.path) {
                DropStore.reset()
                log("Starting fresh store")
                return
            }

            do {
                var shouldLoad = true
                if let dataModified = modificationDate(for: url) {
                    if dataModified == dataFileLastModified {
                        shouldLoad = false
                    } else {
                        dataFileLastModified = dataModified
                    }
                }
                if shouldLoad {
                    log("Needed to reload data, new file date: \(dataFileLastModified)")
                    let start = Date()
                    let result = try dataLoad(from: url)
                    DropStore.initialize(with: result)
                    log("Load time: \(-start.timeIntervalSinceNow) seconds")
                } else {
                    log("No need to reload data")
                }
            } catch {
                log("Loading Error: \(error)")
                loadingError = error as NSError
            }
        }

        if let loadingError {
            handleLoadingError(loadingError)

        } else if let coordinationError {
            handleCoordinationError(coordinationError)
            
        } else {
            trimTemporaryDirectory()
            stateHandler?(.startupComplete)
        }
    }
    
    private static func handleLoadingError(_ error: NSError) {
        brokenMode = true
        log("Error while loading: \(error)")
        let finalError = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
        Task {
            await genericAlert(title: "Loading Error (code \(finalError.code))",
                               message: "This app's data store is not yet accessible. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(error.domain): \(error.localizedDescription)\n\nIf this error persists, please report it to the developer.",
                               buttonTitle: "Quit")
            abort()
        }
    }
    
    private static func handleCoordinationError(_ error: NSError) {
        brokenMode = true
        log("Error in file coordinator: \(error)")
        let finalError = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
        Task {
            await genericAlert(title: "Loading Error (code \(finalError.code))",
                               message: "Could not communicate with an extension. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(error.domain): \(error.localizedDescription)\n\nIf this error persists, please report it to the developer.",
                               buttonTitle: "Quit")
            abort()
        }
    }
    
    public static func resetEverything() {
        let toDelete = DropStore.allDrops.filter { !$0.isImportedShare }
        delete(items: toDelete)
    }

    static func removeImportedShares() {
        let toDelete = DropStore.allDrops.filter(\.isImportedShare)
        delete(items: toDelete)
    }

    static func removeItemsFromZone(_ zoneID: CKRecordZone.ID) {
        let itemsRelatedToZone = DropStore.allDrops.filter { $0.parentZone == zoneID }
        for item in itemsRelatedToZone {
            item.removeFromCloudkit()
        }
        delete(items: itemsRelatedToZone)
    }

    public static func shouldSync(dueToSyncFetch: Bool) async throws -> Bool {
        if dueToSyncFetch {
            log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
            return false

        }
        return await CloudManager.syncSwitchedOn
    }

    public static func duplicate(item: ArchivedItem) {
        if let previousIndex = DropStore.firstIndexOfItem(with: item.uuid) {
            let newItem = ArchivedItem(cloning: item)
            DropStore.insert(drop: newItem, at: previousIndex + 1)
            Task {
                await save()
            }
        }
    }

    public static func delete(items: [ArchivedItem]) {
        for item in items {
            item.delete()
        }
        Task {
            await save()
        }
    }

    public static func lockUnlockedItems() {
        for item in DropStore.allDrops where item.isTemporarilyUnlocked {
            item.flags.insert(.needsUnlock)
            item.postModified()
        }
    }

    private static let badgeTimer = PopTimer(timeInterval: 0.1) {
        badgeHandler?()
    }

    public static func updateBadge() {
        badgeTimer.push()
    }

    static func sortDrops() async {
        let sequence = await CloudManager.uuidSequence.compactMap { UUID(uuidString: $0) }
        DropStore.sortDrops(by: sequence)
    }

    ///////////////////////// Migrating

    private static let indexDelegate = Indexer()

    public static func setup() {
        loadInitialData()
        CSSearchableIndex.default().indexDelegate = indexDelegate

        // migrate if needed
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
        if PersistedOptions.lastRanVersion != currentBuild {
            Task { @CloudActor in
                if CloudManager.syncSwitchedOn, CloudManager.lastiCloudAccount == nil {
                    CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
                }
            }
            stateHandler?(.migrated)
            indexDelegate.searchableIndex(CSSearchableIndex.default()) {
                PersistedOptions.lastRanVersion = currentBuild
            }
        }
    }

    //////////////////////// Saving
    
    public static func save(dueToSyncFetch: Bool = false) async {
        await storageGatekeeper.waitForGate()
        defer {
            storageGatekeeper.signalGate()
        }

        stateHandler?(.willSave)
        
        let index = CSSearchableIndex.default()
        
        let itemsToDelete = Set(DropStore.allDrops.filter(\.needsDeletion))
        let removedUuids = itemsToDelete.map(\.uuid)
        if !removedUuids.isEmpty {
            Task {
                do {
                    try await index.deleteSearchableItems(withIdentifiers: removedUuids.map(\.uuidString))
                } catch {
                    log("Error while deleting search indexes \(error.localizedDescription)")
                }
            }
        }
        
        DropStore.removeDeletableDrops()
        
        let saveableItems: ContiguousArray = DropStore.allDrops.filter(\.goodToSave)
        let itemsToWrite = saveableItems.filter { $0.flags.contains(.needsSaving) }
        if !itemsToWrite.isEmpty {
            Task {
                let searchableItems = itemsToWrite.map(\.searchableItem)
                indexDelegate.reIndex(items: searchableItems, in: index)
            }
        }
        
        let uuidsToEncode = Set(itemsToWrite.map { i -> UUID in
            i.flags.remove(.isBeingCreatedBySync)
            i.flags.remove(.needsSaving)
            return i.uuid
        })
        
        sendNotification(name: .ModelDataUpdated, object: ["updated": uuidsToEncode, "removed": removedUuids])
                
        if brokenMode {
            log("Ignoring save, model is broken, app needs restart.")
        } else {
            await Task.detached(priority: .background) {
                do {
                    try coordinatedSave(allItems: saveableItems, dirtyUuids: uuidsToEncode)
                } catch {
                    log("Saving Error: \(error.finalDescription)")
                }
            }.value
        }
        
        await ComponentLookup.shared.cleanup()
        trimTemporaryDirectory()
        stateHandler?(.saveComplete(dueToSyncFetch: dueToSyncFetch))
    }

    public static func commitItem(item: ArchivedItem) {
        item.flags.remove(.isBeingCreatedBySync)
        item.flags.remove(.needsSaving)

        if brokenMode {
            log("Ignoring save, model is broken, app needs restart.")
            return
        }

        Task {
            await storageGatekeeper.waitForGate()
            defer {
                storageGatekeeper.signalGate()
            }
            if item.needsDeletion || brokenMode {
                return
            }
            let itemsToSave: ContiguousArray<ArchivedItem> = DropStore.allDrops.filter(\.goodToSave)
            indexDelegate.reIndex(items: [item.searchableItem], in: CSSearchableIndex.default())
            await Task.detached(priority: .background) {
                do {
                    _ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: [item.uuid])
                    log("Ingest completed for items (\(item.uuid)) and committed to disk")
                } catch {
                    log("Warning: Error while committing item to disk: (\(error.finalDescription))")
                }
            }.value
        }
    }

    private nonisolated static func coordinatedSave(allItems: ContiguousArray<ArchivedItem>, dirtyUuids: Set<UUID>) throws {
        var closureError: NSError?
        var coordinationError: NSError?
        Coordination.coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
            let start = Date()
            log("Saving: \(allItems.count) uuids, \(dirtyUuids.count) updated data files")
            do {
                let fm = FileManager.default
                let p = url.path
                if !fm.fileExists(atPath: p) {
                    try fm.createDirectory(atPath: p, withIntermediateDirectories: true, attributes: nil)
                }

                let allCount = allItems.count
                let uuidArray = UnsafeMutableBufferPointer<uuid_t>.allocate(capacity: allCount * 16)
                let queue = DispatchQueue(label: "build.bru.gladys.serialisation")
                var count = 0
                let encoder = saveEncoder
                for item in allItems {
                    let u = item.uuid
                    uuidArray[count] = u.uuid
                    count += 1
                    if dirtyUuids.contains(u) {
                        queue.async {
                            let finalPath = url.appendingPathComponent(u.uuidString)
                            try? encoder.encode(item).write(to: finalPath)
                        }
                    }
                }

                let data = queue.sync { Data(buffer: uuidArray) }
                try data.write(to: url.appendingPathComponent("uuids"), options: .atomic)

                if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String], (filesInDir.count - 1) > allCount { // at least one old file exists, let's find it
                    let oldFiles = Set(filesInDir).subtracting(allItems.map(\.uuid.uuidString)).subtracting(["uuids"])
                    for file in oldFiles {
                        log("Removing save file for non-existent item: \(file)")
                        let finalPath = url.appendingPathComponent(file)
                        try? fm.removeItem(at: finalPath)
                    }
                }

                if let dataModified = modificationDate(for: url) {
                    Task { @MainActor in
                        dataFileLastModified = dataModified
                    }
                }

                log("Saved: \(-start.timeIntervalSinceNow) seconds")

            } catch {
                closureError = error as NSError
            }
        }
        if let e = coordinationError ?? closureError {
            throw e
        }
    }

    public static func detectExternalChanges() async {
        for item in DropStore.allDrops where !item.needsDeletion { // partial deletes
            let componentsToDelete = item.components.filter(\.needsDeletion)
            if !componentsToDelete.isEmpty {
                item.components.removeAll { $0.needsDeletion }
                for c in componentsToDelete {
                    await c.deleteFromStorage()
                }
            }
        }
        let itemsToDelete = DropStore.allDrops.filter(\.needsDeletion)
        if !itemsToDelete.isEmpty {
            delete(items: itemsToDelete) // will also save
        }

        await withTaskGroup(of: Void.self) { group in
            for drop in DropStore.allDrops where drop.needsReIngest && !drop.needsDeletion && drop.loadingProgress == nil {
                group.addTask {
                    await drop.reIngest()
                }
            }
        }
    }

    public static func sendToTop(items: [ArchivedItem]) {
        let uuids = Set(items.map(\.uuid))
        DropStore.promoteDropsToTop(uuids: uuids)
        Task {
            await save()
        }
    }

    public static func trimTemporaryDirectory() {
        do {
            let fm = FileManager.default
            let contents = try fm.contentsOfDirectory(atPath: temporaryDirectoryUrl.path)
            let now = Date()
            for name in contents {
                let url = temporaryDirectoryUrl.appendingPathComponent(name)
                let path = url.path
                if (Component.PreviewItem.previewUrls[url] ?? 0) > 0 {
                    log("Temporary directory entry is in use, will skip check: \(path)")
                    continue
                }
                let attributes = try fm.attributesOfItem(atPath: path)
                if let accessDate = (attributes[FileAttributeKey.modificationDate] ?? attributes[FileAttributeKey.creationDate]) as? Date, now.timeIntervalSince(accessDate) > 3600 {
                    log("Temporary directory entry is old, will trim: \(path)")
                    try? fm.removeItem(atPath: path)
                }
            }
        } catch {
            log("Error trimming temporary directory: \(error.localizedDescription)")
        }
    }
}
