import CloudKit
import CoreSpotlight
#if os(iOS)
    import CoreAudioKit
    import Foundation
#else
    import Cocoa
#endif

extension Model {
    static var saveIsDueToSyncFetch = false

    static let saveQueue = DispatchQueue(label: "build.bru.Gladys.saveQueue", qos: .background)
    private static var needsAnotherSave = false
    private static var isSaving = false

    static func sizeInBytes() async -> Int64 {
        let snapshot = allDrops
        return await Task.detached {
            snapshot.reduce(0) { $0 + $1.sizeInBytes }
        }.value
    }

    static func sizeForItems(uuids: [UUID]) async -> Int64 {
        let snapshot = allDrops
        return await Task.detached {
            snapshot.reduce(0) { $0 + (uuids.contains($1.uuid) ? $1.sizeInBytes : 0) }
        }.value
    }

    @MainActor
    enum SortOption {
        case dateAdded, dateModified, title, note, size, label
        var ascendingTitle: String {
            switch self {
            case .dateAdded: return "Oldest Item First"
            case .dateModified: return "Oldest Update First"
            case .title: return "Title (A-Z)"
            case .note: return "Note (A-Z)"
            case .label: return "First Label (A-Z)"
            case .size: return "Smallest First"
            }
        }

        var descendingTitle: String {
            switch self {
            case .dateAdded: return "Newest Item First"
            case .dateModified: return "Newest Update First"
            case .title: return "Title (Z-A)"
            case .note: return "Note (Z-A)"
            case .label: return "First Label (Z-A)"
            case .size: return "Largest First"
            }
        }

        private func sortElements(itemsToSort: ContiguousArray<ArchivedItem>) -> (ContiguousArray<ArchivedItem>, [Int]) {
            var itemIndexes = [Int]()
            let toCheck = itemsToSort.isEmpty ? Model.allDrops : itemsToSort
            let actualItemsToSort = toCheck.compactMap { item -> ArchivedItem? in
                if let index = Model.firstIndexOfItem(with: item.uuid) {
                    itemIndexes.append(index)
                    return item
                }
                return nil
            }
            assert(actualItemsToSort.count == itemIndexes.count)
            return (ContiguousArray(actualItemsToSort), itemIndexes.sorted())
        }

        func handlerForSort(itemsToSort: ContiguousArray<ArchivedItem>, ascending: Bool) -> () -> Void {
            var (actualItemsToSort, itemIndexes) = sortElements(itemsToSort: itemsToSort)
            let sortType = self
            return {
                switch sortType {
                case .dateAdded:
                    if ascending {
                        actualItemsToSort.sort { $0.createdAt < $1.createdAt }
                    } else {
                        actualItemsToSort.sort { $0.createdAt > $1.createdAt }
                    }
                case .dateModified:
                    if ascending {
                        actualItemsToSort.sort { $0.updatedAt < $1.updatedAt }
                    } else {
                        actualItemsToSort.sort { $0.updatedAt > $1.updatedAt }
                    }
                case .title:
                    if ascending {
                        actualItemsToSort.sort { $0.displayTitleOrUuid.localizedCaseInsensitiveCompare($1.displayTitleOrUuid) == .orderedAscending }
                    } else {
                        actualItemsToSort.sort { $0.displayTitleOrUuid.localizedCaseInsensitiveCompare($1.displayTitleOrUuid) == .orderedDescending }
                    }
                case .note:
                    if ascending {
                        actualItemsToSort.sort { $0.note.localizedCaseInsensitiveCompare($1.note) == .orderedAscending }
                    } else {
                        actualItemsToSort.sort { $0.note.localizedCaseInsensitiveCompare($1.note) == .orderedDescending }
                    }
                case .label:
                    if ascending {
                        actualItemsToSort.sort {
                            // treat empty as after Z
                            guard let l1 = $0.labels.first else {
                                return false
                            }
                            guard let l2 = $1.labels.first else {
                                return true
                            }
                            return l1.localizedCaseInsensitiveCompare(l2) == .orderedAscending
                        }
                    } else {
                        actualItemsToSort.sort {
                            // treat empty as after Z
                            guard let l1 = $0.labels.first else {
                                return false
                            }
                            guard let l2 = $1.labels.first else {
                                return true
                            }
                            return l1.localizedCaseInsensitiveCompare(l2) == .orderedDescending
                        }
                    }
                case .size:
                    if ascending {
                        actualItemsToSort.sort { $0.sizeInBytes < $1.sizeInBytes }
                    } else {
                        actualItemsToSort.sort { $0.sizeInBytes > $1.sizeInBytes }
                    }
                }
                for pos in 0 ..< itemIndexes.count {
                    let itemIndex = itemIndexes[pos]
                    let item = actualItemsToSort[pos]
                    Model.replace(drop: item, at: itemIndex)
                }
                Model.saveIndexOnly()
            }
        }

        static var options: [SortOption] { [SortOption.title, SortOption.dateAdded, SortOption.dateModified, SortOption.note, SortOption.label, SortOption.size] }
    }

    static func resetEverything() {
        let toDelete = allDrops.filter { !$0.isImportedShare }
        delete(items: toDelete)
    }

    static func removeImportedShares() {
        let toDelete = allDrops.filter(\.isImportedShare)
        delete(items: toDelete)
    }

    static func removeItemsFromZone(_ zoneID: CKRecordZone.ID) {
        let itemsRelatedToZone = allDrops.filter { $0.parentZone == zoneID }
        for item in itemsRelatedToZone {
            item.removeFromCloudkit()
        }
        delete(items: itemsRelatedToZone)
    }
    
    static func resyncIfNeeded() {
        if saveIsDueToSyncFetch, !CloudManager.syncDirty {
            saveIsDueToSyncFetch = false
            log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
        } else {
            if CloudManager.syncDirty {
                log("A sync had been requested while syncing, evaluating another sync")
            }
            CloudManager.syncAfterSaveIfNeeded()
        }
    }

    static var sharingMyItems: Bool {
        allDrops.contains { $0.shareMode == .sharing }
    }

    static var containsImportedShares: Bool {
        allDrops.contains { $0.isImportedShare }
    }

    static var itemsIAmSharing: ContiguousArray<ArchivedItem> {
        allDrops.filter { $0.shareMode == .sharing }
    }

    static func duplicate(item: ArchivedItem) {
        if let previousIndex = firstIndexOfItem(with: item.uuid) {
            let newItem = ArchivedItem(cloning: item)
            insert(drop: newItem, at: previousIndex + 1)
            save()
        }
    }

    static func delete(items: [ArchivedItem]) {
        for item in items {
            item.delete()
        }
        save()
    }

    static func lockUnlockedItems() {
        for item in allDrops where item.isTemporarilyUnlocked {
            item.flags.insert(.needsUnlock)
            item.postModified()
        }
    }

    static let badgeTimer = PopTimer(timeInterval: 0.1) {
        Task {
            _updateBadge()
        }
    }

    static func updateBadge() {
        badgeTimer.push()
    }

    static func sortDrops() {
        let sequence = CloudManager.uuidSequence.compactMap { UUID(uuidString: $0) }
        sortDrops(by: sequence)
    }

    ///////////////////////// Migrating

    static func setup() {
        reloadDataIfNeeded()
        setupIndexDelegate()

        // migrate if needed
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
        if PersistedOptions.lastRanVersion != currentBuild {
            if CloudManager.syncSwitchedOn, CloudManager.lastiCloudAccount == nil {
                CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
            }
            #if os(iOS)
                Model.clearLegacyIntents()
            #endif
            Model.searchableIndex(CSSearchableIndex.default()) {
                PersistedOptions.lastRanVersion = currentBuild
            }
        }
    }

    //////////////////////// Saving

    static func save(force: Bool = false) {
        if !force, isSaving {
            needsAnotherSave = true
            return
        }
        
        prepareToSave()
        
        let index = CSSearchableIndex.default()

        let itemsToDelete = Set(allDrops.filter(\.needsDeletion))
        #if MAINAPP
            MirrorManager.removeItems(items: itemsToDelete)
        #endif

        let removedUuids = itemsToDelete.map(\.uuid)
        index.deleteSearchableItems(withIdentifiers: removedUuids.map(\.uuidString)) { error in
            if let error {
                log("Error while deleting search indexes \(error.localizedDescription)")
            }
        }

        removeDeletableDrops()

        let saveableItems: ContiguousArray = allDrops.filter(\.goodToSave)
        let itemsToWrite = saveableItems.filter { $0.flags.contains(.needsSaving) }
        if !itemsToWrite.isEmpty {
            let searchableItems = itemsToWrite.map(\.searchableItem)
            reIndex(items: searchableItems, in: index)
        }

        let uuidsToEncode = Set(itemsToWrite.map { i -> UUID in
            i.flags.remove(.isBeingCreatedBySync)
            i.flags.remove(.needsSaving)
            return i.uuid
        })

        isSaving = true
        needsAnotherSave = false

        sendNotification(name: .ModelDataUpdated, object: ["updated": uuidsToEncode, "removed": removedUuids])

        saveQueue.async {
            do {
                try coordinatedSave(allItems: saveableItems, dirtyUuids: uuidsToEncode)
            } catch {
                log("Saving Error: \(error.finalDescription)")
            }

            Task {
                await ComponentLookup.shared.cleanup()
            }

            Task { @MainActor in
                if needsAnotherSave {
                    save(force: true)
                } else {
                    isSaving = false
                    trimTemporaryDirectory()
                    saveComplete()
                }
            }
        }
    }

    static func saveIndexOnly() {
        let itemsToSave: ContiguousArray = allDrops.filter(\.goodToSave)
        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil)
        saveQueue.async {
            do {
                _ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: [])
                log("Saved index only")
            } catch {
                log("Warning: Error while committing index to disk: (\(error.finalDescription))")
            }
            Task { @MainActor in
                saveIndexComplete()
            }
        }
    }

    private static var commitQueue = ContiguousArray<ArchivedItem>()
    static func commitItem(item: ArchivedItem) {
        item.flags.remove(.isBeingCreatedBySync)
        item.flags.remove(.needsSaving)
        commitQueue.append(item)

        reIndex(items: [item.searchableItem], in: CSSearchableIndex.default())

        saveQueue.async {
            var nextItemUUIDs = Set<UUID>()
            var itemsToSave = ContiguousArray<ArchivedItem>()
            DispatchQueue.main.sync {
                nextItemUUIDs = Set(commitQueue.filter { !$0.needsDeletion }.map(\.uuid))
                commitQueue.removeAll()
                itemsToSave = allDrops.filter(\.goodToSave)
            }
            if nextItemUUIDs.isEmpty {
                return
            }
            do {
                _ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: nextItemUUIDs)
                log("Ingest completed for items (\(nextItemUUIDs)) and committed to disk")
            } catch {
                log("Warning: Error while committing item to disk: (\(error.finalDescription))")
            }
        }
    }

    private static func coordinatedSave(allItems: ContiguousArray<ArchivedItem>, dirtyUuids: Set<UUID>) throws {
        if brokenMode {
            log("Ignoring save, model is broken, app needs restart.")
            return
        }
        var closureError: NSError?
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
            let start = Date()
            log("Saving: \(allItems.count) uuids, \(dirtyUuids.count) updated data files")
            do {
                let fm = FileManager.default
                let p = url.path
                if !fm.fileExists(atPath: p) {
                    try fm.createDirectory(atPath: p, withIntermediateDirectories: true, attributes: nil)
                }

                let allCount = allItems.count
                var uuidData = Data(count: allCount * 16)
                let encoder = saveEncoder
                uuidData.withUnsafeMutableBytes { unsafeMutableRawBufferPointer in
                    let uuidArray = unsafeMutableRawBufferPointer.bindMemory(to: uuid_t.self)
                    var count = 0
                    for item in allItems {
                        let u = item.uuid
                        uuidArray[count] = u.uuid
                        count += 1
                        if dirtyUuids.contains(u) {
                            let finalPath = url.appendingPathComponent(u.uuidString)
                            try? encoder.encode(item).write(to: finalPath)
                        }
                    }
                }
                try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

                if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String], (filesInDir.count - 1) > allCount { // at least one old file exists, let's find it
                    let oldFiles = Set(filesInDir).subtracting(allItems.map(\.uuid.uuidString)).subtracting(["uuids"])
                    for file in oldFiles {
                        log("Removing save file for non-existent item: \(file)")
                        let finalPath = url.appendingPathComponent(file)
                        try? fm.removeItem(at: finalPath)
                    }
                }

                if let dataModified = modificationDate(for: url) {
                    dataFileLastModified = dataModified
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

    static func detectExternalChanges() async {
        for item in allDrops where !item.needsDeletion { // partial deletes
            let componentsToDelete = item.components.filter(\.needsDeletion)
            if !componentsToDelete.isEmpty {
                item.components.removeAll { $0.needsDeletion }
                for c in componentsToDelete {
                    c.deleteFromStorage()
                }
                item.needsReIngest = true
            }
        }
        let itemsToDelete = allDrops.filter(\.needsDeletion)
        if !itemsToDelete.isEmpty {
            delete(items: itemsToDelete) // will also save
        }

        await withTaskGroup(of: Void.self) { group in
            for drop in allDrops where drop.needsReIngest && !drop.needsDeletion && drop.loadingProgress == nil {
                group.addTask {
                    await drop.reIngest()
                }
            }
        }
    }

    static func sendToTop(items: [ArchivedItem]) {
        let uuids = Set(items.map(\.uuid))
        promoteDropsToTop(uuids: uuids)
        saveIndexOnly()
    }
}
