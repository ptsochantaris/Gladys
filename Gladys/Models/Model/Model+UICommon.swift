import CloudKit
import CoreSpotlight
#if os(macOS)
    import Cocoa
#else
    import CoreAudioKit
    import Foundation
#endif
import GladysCommon

@globalActor
enum ModelStorage {
    final actor ActorType {}
    static let shared = ActorType()
}

extension Model {
    static var saveIsDueToSyncFetch = false

    private static var needsAnotherSave = false
    private static var isSaving = false

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
            let toCheck = itemsToSort.isEmpty ? DropStore.allDrops : itemsToSort
            let actualItemsToSort = toCheck.compactMap { item -> ArchivedItem? in
                if let index = DropStore.firstIndexOfItem(with: item.uuid) {
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
                    DropStore.replace(drop: item, at: itemIndex)
                }
                Model.saveIndexOnly()
            }
        }

        static var options: [SortOption] { [SortOption.title, SortOption.dateAdded, SortOption.dateModified, SortOption.note, SortOption.label, SortOption.size] }
    }

    static func resetEverything() {
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

    static func resyncIfNeeded() async throws {
        let syncDirty = await CloudManager.syncDirty
        if saveIsDueToSyncFetch, !syncDirty {
            saveIsDueToSyncFetch = false
            log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
        } else {
            if syncDirty {
                log("A sync had been requested while syncing, evaluating another sync")
            }
            try await CloudManager.syncAfterSaveIfNeeded()
        }
    }

    static var sharingMyItems: Bool {
        DropStore.allDrops.contains { $0.shareMode == .sharing }
    }

    static var containsImportedShares: Bool {
        DropStore.allDrops.contains { $0.isImportedShare }
    }

    static var itemsIAmSharing: ContiguousArray<ArchivedItem> {
        DropStore.allDrops.filter { $0.shareMode == .sharing }
    }

    static func duplicate(item: ArchivedItem) {
        if let previousIndex = DropStore.firstIndexOfItem(with: item.uuid) {
            let newItem = ArchivedItem(cloning: item)
            DropStore.insert(drop: newItem, at: previousIndex + 1)
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
        for item in DropStore.allDrops where item.isTemporarilyUnlocked {
            item.flags.insert(.needsUnlock)
            item.postModified()
        }
    }

    static let badgeTimer = PopTimer(timeInterval: 0.1) {
        Task {
            await _updateBadge()
        }
    }

    static func updateBadge() {
        badgeTimer.push()
    }

    static func sortDrops() async {
        let sequence = await CloudManager.uuidSequence.compactMap { UUID(uuidString: $0) }
        DropStore.sortDrops(by: sequence)
    }

    ///////////////////////// Migrating

    static func setup() {
        reloadDataIfNeeded()
        setupIndexDelegate()

        // migrate if needed
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
        if PersistedOptions.lastRanVersion != currentBuild {
            Task { @CloudActor in
                if CloudManager.syncSwitchedOn, CloudManager.lastiCloudAccount == nil {
                    CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
                }
            }
            #if os(macOS)
            #else
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

        let itemsToDelete = Set(DropStore.allDrops.filter(\.needsDeletion))
        let removedUuids = itemsToDelete.map(\.uuid)
        index.deleteSearchableItems(withIdentifiers: removedUuids.map(\.uuidString)) { error in
            if let error {
                log("Error while deleting search indexes \(error.localizedDescription)")
            }
        }

        DropStore.removeDeletableDrops()

        let saveableItems: ContiguousArray = DropStore.allDrops.filter(\.goodToSave)
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

        let broken = brokenMode

        Task { @ModelStorage in
            if broken {
                log("Ignoring save, model is broken, app needs restart.")
            } else {
                do {
                    try coordinatedSave(allItems: saveableItems, dirtyUuids: uuidsToEncode)
                } catch {
                    log("Saving Error: \(error.finalDescription)")
                }
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
        let itemsToSave: ContiguousArray = DropStore.allDrops.filter(\.goodToSave)
        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil)
        let broken = brokenMode

        Task { @ModelStorage in
            if broken {
                log("Ignoring save, model is broken, app needs restart.")
            } else {
                do {
                    _ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: [])
                    log("Saved index only")
                } catch {
                    log("Warning: Error while committing index to disk: (\(error.finalDescription))")
                }
            }
            Task { @MainActor in
                saveIndexComplete()
            }
        }
    }

    private static let commitQueue = LinkedList<ArchivedItem>()
    static func commitItem(item: ArchivedItem) {
        item.flags.remove(.isBeingCreatedBySync)
        item.flags.remove(.needsSaving)

        if brokenMode {
            log("Ignoring save, model is broken, app needs restart.")
            return
        }

        commitQueue.append(item)

        Task { @ModelStorage in
            let (itemsToCommit, itemsToSave) = await MainActor.run {
                let itemsToCommit = commitQueue.filter { !$0.needsDeletion }
                commitQueue.removeAll()
                reIndex(items: itemsToCommit.map(\.searchableItem), in: CSSearchableIndex.default())
                let itemsToSave: ContiguousArray<ArchivedItem> = DropStore.allDrops.filter(\.goodToSave)
                return (itemsToCommit, itemsToSave)
            }
            if itemsToCommit.isEmpty {
                return
            }
            let nextItemUUIDs = Set(itemsToCommit.map(\.uuid))
            do {
                _ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: nextItemUUIDs)
                log("Ingest completed for items (\(nextItemUUIDs)) and committed to disk")
            } catch {
                log("Warning: Error while committing item to disk: (\(error.finalDescription))")
            }
        }
    }

    @ModelStorage
    private static func coordinatedSave(allItems: ContiguousArray<ArchivedItem>, dirtyUuids: Set<UUID>) throws {
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
                let uuidArray = UnsafeMutableBufferPointer<uuid_t>.allocate(capacity: allCount * 16)
                let queue = DispatchQueue(label: "build.bru.gladys.serialisation")
                var count = 0
                let encoder = saveEncoder()
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

                Task { @MainActor in
                    if let dataModified = modificationDate(for: url) {
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

    static func detectExternalChanges() async {
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

    static func sendToTop(items: [ArchivedItem]) {
        let uuids = Set(items.map(\.uuid))
        DropStore.promoteDropsToTop(uuids: uuids)
        saveIndexOnly()
    }
}
