import Foundation
import GladysCommon

@MainActor
enum Model {
    private static var uuidindex: [UUID: Int]?

    private static var dropStore = ContiguousArray<ArchivedItem>()

    static var allDrops: ContiguousArray<ArchivedItem> {
        dropStore
    }

    static func insert(drop: ArchivedItem, at index: Int) {
        dropStore.insert(drop, at: index)
        uuidindex = nil
    }

    static func replace(drop: ArchivedItem, at index: Int) {
        dropStore[index] = drop
        uuidindex = nil
    }

    static func removeDrop(at index: Int) {
        let item = dropStore.remove(at: index)
        uuidindex?[item.uuid] = nil
    }

    static var dropsAreEmpty: Bool {
        dropStore.isEmpty
    }

    static func sortDrops(by sequence: [UUID]) {
        if sequence.isEmpty { return }
        dropStore.sort { i1, i2 in
            let p1 = sequence.firstIndex(of: i1.uuid) ?? -1
            let p2 = sequence.firstIndex(of: i2.uuid) ?? -1
            return p1 < p2
        }
        uuidindex = nil
    }

    static func removeDeletableDrops() {
        let count = dropStore.count
        dropStore.removeAll { $0.needsDeletion }
        if count != dropStore.count {
            uuidindex = nil
        }
    }

    static func promoteDropsToTop(uuids: Set<UUID>) {
        let cut = dropStore.filter { uuids.contains($0.uuid) }
        if cut.isEmpty { return }
        dropStore.removeAll { uuids.contains($0.uuid) }
        dropStore.insert(contentsOf: cut, at: 0)
        uuidindex = nil
    }

    static func append(drop: ArchivedItem) {
        uuidindex?[drop.uuid] = dropStore.count
        dropStore.append(drop)
    }

    static func firstIndexOfItem(with uuid: UUID) -> Int? {
        if let uuidindex {
            return uuidindex[uuid]
        } else {
            let z = zip(dropStore.map(\.uuid), 0 ..< dropStore.count)
            let newIndex = Dictionary(z) { one, _ in one }
            uuidindex = newIndex
            log("Rebuilt drop index")
            return newIndex[uuid]
        }
    }

    static func firstItem(with uuid: UUID) -> ArchivedItem? {
        if let i = firstIndexOfItem(with: uuid) {
            return dropStore[i]
        }
        return nil
    }

    static func firstIndexOfItem(with uuid: String) -> Int? {
        if let uuidData = UUID(uuidString: uuid) {
            return firstIndexOfItem(with: uuidData)
        }
        return nil
    }

    static func contains(uuid: UUID) -> Bool {
        firstIndexOfItem(with: uuid) != nil
    }

    static func clearCaches() {
        for drop in dropStore {
            for component in drop.components {
                component.clearCachedFields()
            }
        }
    }

    ////////////////////////////////////////

    static var brokenMode = false
    static var dataFileLastModified = Date.distantPast

    private static var isStarted = false

    static func reset() {
        dropStore.removeAll(keepingCapacity: false)
        uuidindex = [:]
        clearCaches()
        dataFileLastModified = .distantPast
    }

    nonisolated static func loadDecoder() -> JSONDecoder {
        log("Creating new loading decoder")
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
        return decoder
    }

    nonisolated static func saveEncoder() -> JSONEncoder {
        log("Creating new saving encoder")
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
        return encoder
    }

    private final class LoaderBuffer {
        private let queue = DispatchQueue(label: "build.bru.gladys.deserialisation")

        private var store: ContiguousArray<ArchivedItem?>

        init(capacity: Int) {
            store = ContiguousArray<ArchivedItem?>(repeating: nil, count: capacity)
        }

        func set(_ item: ArchivedItem, at index: Int) {
            queue.async {
                self.store[index] = item
            }
        }

        func result() -> ContiguousArray<ArchivedItem> {
            queue.sync {
                ContiguousArray(store.compactMap { $0 })
            }
        }
    }

    static func reloadDataIfNeeded(maximumItems: Int? = nil) {
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
                dropStore.removeAll(keepingCapacity: false)
                uuidindex = [:]
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
                    dropStore = loader.result()
                    uuidindex = nil
                    log("Load time: \(-start.timeIntervalSinceNow) seconds")
                } else {
                    log("No need to reload data")
                }
            } catch {
                log("Loading Error: \(error)")
                loadingError = error as NSError
            }
        }

        if let e = loadingError {
            brokenMode = true
            log("Error in loading: \(e)")
            #if MAINAPP || MAC
                let finalError: NSError
                if let underlyingError = e.userInfo[NSUnderlyingErrorKey] as? NSError {
                    finalError = underlyingError
                } else {
                    finalError = e
                }
                Task {
                    await genericAlert(title: "Loading Error (code \(finalError.code))",
                                       message: "This app's data store is not yet accessible. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(e.domain): \(e.localizedDescription)\n\nIf this error persists, please report it to the developer.",
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

        } else if let e = coordinationError {
            log("Error in file coordinator: \(e)")
            #if MAINAPP || MAC
                let finalError: NSError
                if let underlyingError = e.userInfo[NSUnderlyingErrorKey] as? NSError {
                    finalError = underlyingError
                } else {
                    finalError = e
                }
                Task {
                    await genericAlert(title: "Loading Error (code \(finalError.code))",
                                       message: "Could not communicate with an extension. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(e.domain): \(e.localizedDescription)\n\nIf this error persists, please report it to the developer.",
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
                startupComplete()
            }
        }
    }

    static var doneIngesting: Bool {
        !dropStore.contains { ($0.needsReIngest && !$0.needsDeletion) || $0.loadingProgress != nil }
    }

    static var visibleDrops: ContiguousArray<ArchivedItem> {
        dropStore.filter(\.isVisible)
    }

    static let itemsDirectoryUrl: URL = appStorageUrl.appendingPathComponent("items", isDirectory: true)

    static let temporaryDirectoryUrl: URL = {
        let url = appStorageUrl.appendingPathComponent("temporary", isDirectory: true)
        let fm = FileManager.default
        let p = url.path
        if fm.fileExists(atPath: p) {
            try? fm.removeItem(atPath: p)
        }
        try! fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }()

    static func item(uuid: String) -> ArchivedItem? {
        if let uuidData = UUID(uuidString: uuid) {
            return item(uuid: uuidData)
        } else {
            return nil
        }
    }

    static func item(uuid: UUID) -> ArchivedItem? {
        firstItem(with: uuid)
    }

    static func item(shareId: String) -> ArchivedItem? {
        dropStore.first { $0.cloudKitRecord?.share?.recordID.recordName == shareId }
    }

    static func component(uuid: UUID) async -> Component? {
        await ComponentLookup.shared.lookup(uuid: uuid)
    }

    static func component(uuid: String) async -> Component? {
        if let uuidData = UUID(uuidString: uuid) {
            return await component(uuid: uuidData)
        } else {
            return nil
        }
    }

    static func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static let appStorageUrl: URL = {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
        #if MAC
            log("Model URL: \(url.path)")
            return url
        #else
            let fps = url.appendingPathComponent("File Provider Storage")
            log("Model URL: \(fps.path)")
            return fps
        #endif
    }()
}
