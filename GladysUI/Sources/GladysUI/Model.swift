import CloudKit
import CoreSpotlight
import Foundation
import GladysCommon
import UniformTypeIdentifiers
import ZIPFoundation
#if canImport(Cocoa)
    import Cocoa
#endif

@globalActor
enum ModelStorage {
    final actor ActorType {}
    static let shared = ActorType()
}

extension UTType {
    public static let gladysArchive = UTType(tag: "gladysArchive", tagClass: .filenameExtension, conformingTo: .bundle)!
}

@MainActor
public enum Model {
    public enum State {
        case startupComplete, willSave, saveComplete, migrated
    }

    private static var dataFileLastModified = Date.distantPast
    private static var isStarted = false
    private static var needsAnotherSave = false
    private static var isSaving = false

    public static var brokenMode = false
    public static var saveIsDueToSyncFetch = false
    public static var badgeHandler: (() -> Void)?
    public static var stateHandler: ((State) -> Void)?
    
    static func reset() {
        DropStore.reset()
        dataFileLastModified = .distantPast
    }

    public static func reloadDataIfNeeded(maximumItems: Int? = nil) {
        if brokenMode {
            log("Ignoring load, model is broken, app needs restart.")
            return
        }

        var coordinationError: NSError?
        var loadingError: NSError?
        var didLoad = false

        // withoutChanges because we only signal the provider after we have saved
        coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

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
                    didLoad = true

                    let start = Date()

                    let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
                    let totalItemsInStore = d.count / 16
                    let itemCount: Int
                    if let maximumItems {
                        itemCount = min(maximumItems, totalItemsInStore)
                    } else {
                        itemCount = totalItemsInStore
                    }

                    let loader = LoaderBuffer(capacity: itemCount)
                    d.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                        let decoder = loadDecoder()
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
                    DropStore.initialize(with: loader.result())
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
            brokenMode = true
            log("Error in loading: \(loadingError)")
            #if MAINAPP || MAC
                let finalError: NSError
                if let underlyingError = loadingError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    finalError = underlyingError
                } else {
                    finalError = loadingError
                }
                Task {
                    await genericAlert(title: "Loading Error (code \(finalError.code))",
                                       message: "This app's data store is not yet accessible. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(loadingError.domain): \(loadingError.localizedDescription)\n\nIf this error persists, please report it to the developer.",
                                       buttonTitle: "Quit")
                    abort()
                }
            #else
                // still boot the item, so it doesn't block others, but keep blank contents and abort after a second or two
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2000 * NSEC_PER_MSEC)
                    exit(0)
                }
            #endif

        } else if let coordinationError {
            brokenMode = true
            log("Error in file coordinator: \(coordinationError)")
            #if MAINAPP || MAC
                let finalError: NSError
                if let underlyingError = coordinationError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    finalError = underlyingError
                } else {
                    finalError = coordinationError
                }
                Task {
                    await genericAlert(title: "Loading Error (code \(finalError.code))",
                                       message: "Could not communicate with an extension. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(coordinationError.domain): \(coordinationError.localizedDescription)\n\nIf this error persists, please report it to the developer.",
                                       buttonTitle: "Quit")
                    abort()
                }
            #else
                exit(0)
            #endif
        }

        if !brokenMode {
            if isStarted {
                if didLoad {
                    Task { @MainActor in
                        sendNotification(name: .ModelDataUpdated, object: nil)
                    }
                }
            } else {
                isStarted = true
                stateHandler?(.startupComplete)
            }
        }
    }

    @MainActor
    public enum SortOption {
        case dateAdded, dateModified, title, note, size, label
        public var ascendingTitle: String {
            switch self {
            case .dateAdded: return "Oldest Item First"
            case .dateModified: return "Oldest Update First"
            case .title: return "Title (A-Z)"
            case .note: return "Note (A-Z)"
            case .label: return "First Label (A-Z)"
            case .size: return "Smallest First"
            }
        }

        public var descendingTitle: String {
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

        public func handlerForSort(itemsToSort: ContiguousArray<ArchivedItem>, ascending: Bool) -> () -> Void {
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
                Model.save()
            }
        }

        public static var options: [SortOption] { [SortOption.title, SortOption.dateAdded, SortOption.dateModified, SortOption.note, SortOption.label, SortOption.size] }
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

    public static func resyncIfNeeded() async throws -> Bool {
        if await CloudManager.syncDirty {
            log("A sync had been requested while syncing, will attempt another sync")
            return true
            
        } else if saveIsDueToSyncFetch {
            saveIsDueToSyncFetch = false
            log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
            return false
            
        } else if await CloudManager.syncSwitchedOn {
            log("Will sync after a save")
            return true
            
        } else {
            return false
        }
    }

    public static func duplicate(item: ArchivedItem) {
        if let previousIndex = DropStore.firstIndexOfItem(with: item.uuid) {
            let newItem = ArchivedItem(cloning: item)
            DropStore.insert(drop: newItem, at: previousIndex + 1)
            save()
        }
    }

    public static func delete(items: [ArchivedItem]) {
        for item in items {
            item.delete()
        }
        save()
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
        reloadDataIfNeeded()
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

    public static func save(force: Bool = false) {
        if !force, isSaving {
            needsAnotherSave = true
            return
        }

        stateHandler?(.willSave)

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
            indexDelegate.reIndex(items: searchableItems, in: index)
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
                    stateHandler?(.saveComplete)
                }
            }
        }
    }

    private static let commitQueue = LinkedList<ArchivedItem>()
    public static func commitItem(item: ArchivedItem) {
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
                indexDelegate.reIndex(items: itemsToCommit.map(\.searchableItem), in: CSSearchableIndex.default())
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
        save()
    }

    private static func bringInItem(_ item: ArchivedItem, from url: URL, using fm: FileManager, moveItem: Bool) throws -> Bool {
        let remotePath = url.appendingPathComponent(item.uuid.uuidString)
        if !fm.fileExists(atPath: remotePath.path) {
            log("Warning: Item \(item.uuid) declared but not found on imported archive, skipped")
            return false
        }

        if moveItem {
            try fm.moveAndReplaceItem(at: remotePath, to: item.folderUrl)
        } else {
            try fm.copyAndReplaceItem(at: remotePath, to: item.folderUrl)
        }

        item.needsReIngest = true
        item.markUpdated()
        item.removeFromCloudkit()

        return true
    }

    public static func importArchive(from url: URL, removingOriginal: Bool) throws {
        let fm = FileManager.default
        defer {
            if removingOriginal {
                try? fm.removeItem(at: url)
            }
            save()
        }

        let finalPath = url.appendingPathComponent("items.json")
        guard let data = Data.forceMemoryMapped(contentsOf: finalPath) else {
            throw GladysError.importingArchiveFailed.error
        }
        let itemsInPackage = try loadDecoder().decode([ArchivedItem].self, from: data)

        for item in itemsInPackage.reversed() {
            if let i = DropStore.firstIndexOfItem(with: item.uuid) {
                if DropStore.allDrops[i].updatedAt >= item.updatedAt || DropStore.allDrops[i].shareMode != .none {
                    continue
                }
                if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    DropStore.replace(drop: item, at: i)
                }
            } else {
                if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    DropStore.insert(drop: item, at: 0)
                }
            }
        }
    }

    private class FileManagerFilter: NSObject, FileManagerDelegate {
        func fileManager(_: FileManager, shouldCopyItemAt srcURL: URL, to _: URL) -> Bool {
            guard let lastComponent = srcURL.pathComponents.last else { return false }
            return !(lastComponent == "shared-blob" || lastComponent == "ck-record" || lastComponent == "ck-share")
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @discardableResult
    public static func createArchive(using filter: Filter, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        let eligibleItems: ContiguousArray = filter.eligibleDropsForExport.filter { !$0.isImportedShare }
        let count = 2 + eligibleItems.count
        let p = Progress(totalUnitCount: Int64(count))

        Task.detached {
            do {
                let url = try createArchiveThread(progress: p, eligibleItems: eligibleItems)
                completion(url, nil)
            } catch {
                completion(nil, error)
            }
        }

        return p
    }

    private nonisolated static func createArchiveThread(progress p: Progress, eligibleItems: ContiguousArray<ArchivedItem>) throws -> URL {
        let fm = FileManager()
        let tempPath = temporaryDirectoryUrl.appendingPathComponent("Gladys Archive.gladysArchive")
        let path = tempPath.path
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }

        let delegate = FileManagerFilter()
        fm.delegate = delegate

        p.completedUnitCount += 1

        try fm.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)
        for item in eligibleItems {
            let uuidString = item.uuid.uuidString
            let sourceForItem = appStorageUrl.appendingPathComponent(uuidString)
            let destinationForItem = tempPath.appendingPathComponent(uuidString)
            try fm.copyAndReplaceItem(at: sourceForItem, to: destinationForItem)
            p.completedUnitCount += 1
        }

        let data = try saveEncoder().encode(eligibleItems)
        let finalPath = tempPath.appendingPathComponent("items.json")
        try data.write(to: finalPath)
        p.completedUnitCount += 1

        return tempPath
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @discardableResult
    public static func createZip(using filter: Filter, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        let dropsCopy = filter.eligibleDropsForExport
        let itemCount = Int64(1 + dropsCopy.count)
        let p = Progress(totalUnitCount: itemCount)

        Task.detached {
            do {
                let url = try await createZipThread(dropsCopy: dropsCopy, progress: p)
                completion(url, nil)
            } catch {
                completion(nil, error)
            }
        }

        return p
    }

    static func createZipThread(dropsCopy: ContiguousArray<ArchivedItem>, progress p: Progress) async throws -> URL {
        let tempPath = temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

        let fm = FileManager.default
        let path = tempPath.path
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }

        p.completedUnitCount += 1

        if let archive = Archive(url: tempPath, accessMode: .create) {
            for item in dropsCopy {
                let dir = item.displayTitleOrUuid.filenameSafe

                if item.components.count == 1, let typeItem = item.components.first {
                    try await addZipItem(typeItem, directory: nil, name: dir, in: archive)

                } else {
                    for typeItem in item.components {
                        try await addZipItem(typeItem, directory: dir, name: typeItem.typeDescription, in: archive)
                    }
                }
                p.completedUnitCount += 1
            }
        }

        return tempPath
    }

    private static func addZipItem(_ typeItem: Component, directory: String?, name: String, in archive: Archive) async throws {
        var bytes: Data?
        if typeItem.isWebURL, let url = typeItem.encodedUrl {
            bytes = url.urlFileContent

        } else if typeItem.classWasWrapped {
            bytes = typeItem.dataForDropping ?? typeItem.bytes
        }
        if let B = bytes ?? typeItem.bytes {
            let timmedName = typeItem.prepareFilename(name: name, directory: directory)
            let provider: Provider = { (pos: Int64, size: Int) throws -> Data in
                B[pos ..< pos + Int64(size)]
            }
            try archive.addEntry(with: timmedName, type: .file, uncompressedSize: Int64(B.count), provider: provider)
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
