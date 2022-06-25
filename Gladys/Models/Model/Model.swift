import Foundation

final class Model {
    private static var uuidindex: [UUID: Int]?

    static var drops = ContiguousArray<ArchivedItem>() {
        didSet {
            assert(Thread.isMainThread)
            uuidindex = nil
        }
    }

    @MainActor
    static func appendDropEfficientlyAsync(_ newDrop: ArchivedItem) {
        appendDropEfficiently(newDrop)
    }

    static func appendDropEfficiently(_ newDrop: ArchivedItem) {
        uuidindex?[newDrop.uuid] = drops.count

        let previousIndex = uuidindex
        drops.append(newDrop)
        uuidindex = previousIndex
    }

    private static func rebuildIndexIfNeeded() {
        if uuidindex == nil {
            // assert(Thread.isMainThread)
            let d = drops // copy
            let z = zip(d.map(\.uuid), 0 ..< d.count)
            uuidindex = Dictionary(z) { one, _ in one }
            log("Rebuilt drop index")
        }
    }

    static func firstIndexOfItem(with uuid: UUID) -> Int? {
        if Thread.isMainThread {
            return _firstIndexOfItem(with: uuid)
        } else {
            return DispatchQueue.main.sync {
                return _firstIndexOfItem(with: uuid)
            }
        }
    }
    
    private static func _firstIndexOfItem(with uuid: UUID) -> Int? {
        rebuildIndexIfNeeded()
        return uuidindex?[uuid]
    }

    static func firstItem(with uuid: UUID) -> ArchivedItem? {
        if Thread.isMainThread {
            return _firstItem(with: uuid)
        } else {
            return DispatchQueue.main.sync {
                return _firstItem(with: uuid)
            }
        }
    }
    
    private static func _firstItem(with uuid: UUID) -> ArchivedItem? {
        if let i = firstIndexOfItem(with: uuid) {
            return drops[i]
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
        for drop in drops {
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
        drops.removeAll(keepingCapacity: false)
        clearCaches()
        dataFileLastModified = .distantPast
    }

    static var loadDecoder: JSONDecoder {
        if let decoder = Thread.current.threadDictionary["gladys.decoder"] as? JSONDecoder {
            return decoder
        } else {
            log("Creating new loading decoder")
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
            Thread.current.threadDictionary["gladys.decoder"] = decoder
            return decoder
        }
    }

    static var saveEncoder: JSONEncoder {
        if let encoder = Thread.current.threadDictionary["gladys.encoder"] as? JSONEncoder {
            return encoder
        } else {
            log("Creating new saving encoder")
            let encoder = JSONEncoder()
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
            Thread.current.threadDictionary["gladys.encoder"] = encoder
            return encoder
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
                drops.removeAll(keepingCapacity: false)
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
                    if let maximumItems = maximumItems {
                        itemCount = min(maximumItems, totalItemsInStore)
                    } else {
                        itemCount = totalItemsInStore
                    }

                    var newDrops = ContiguousArray<ArchivedItem>()
                    let loadQueue = DispatchQueue(label: "build.bru.Gladys.loadDecoderQueue", autoreleaseFrequency: .never)
                    loadQueue.async {
                        newDrops.reserveCapacity(itemCount)
                    }
                    d.withUnsafeBytes { pointer in
                        let uuidSequence = pointer.bindMemory(to: uuid_t.self).prefix(itemCount)
                        uuidSequence.forEach { u in
                            let u = UUID(uuid: u)
                            let dataPath = url.appendingPathComponent(u.uuidString)
                            if let data = try? Data(contentsOf: dataPath) {
                                loadQueue.async {
                                    if let item = try? loadDecoder.decode(ArchivedItem.self, from: data) {
                                        newDrops.append(item)
                                    }
                                }
                            }
                        }
                    }

                    drops = loadQueue.sync { newDrops }
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
                return
            #else
                // still boot the item, so it doesn't block others, but keep blank contents and abort after a second or two
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
                return
            #else
                exit(0)
            #endif
        }

        if !brokenMode {
            DispatchQueue.main.async {
                if isStarted {
                    if didLoad {
                        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil)
                    }
                } else {
                    isStarted = true
                    startupComplete()
                }
            }
        }
    }

    static var doneIngesting: Bool {
        !drops.contains { ($0.needsReIngest && !$0.needsDeletion) || $0.loadingProgress != nil }
    }

    static var visibleDrops: ContiguousArray<ArchivedItem> {
        drops.filter(\.isVisible)
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

    @MainActor
    static func itemAsync(uuid: String) -> ArchivedItem? {
        item(uuid: uuid)
    }

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

    @MainActor
    static func itemAsync(shareId: String) -> ArchivedItem? {
        item(shareId: shareId)
    }

    static func item(shareId: String) -> ArchivedItem? {
        drops.first { $0.cloudKitRecord?.share?.recordID.recordName == shareId }
    }

    static func component(uuid: UUID) -> Component? {
        Component.lookup(uuid: uuid)
    }

    static func component(uuid: String) -> Component? {
        if let uuidData = UUID(uuidString: uuid) {
            return component(uuid: uuidData)
        } else {
            return nil
        }
    }

    @MainActor
    static func componentAsync(uuid: String) -> Component? {
        component(uuid: uuid)
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
