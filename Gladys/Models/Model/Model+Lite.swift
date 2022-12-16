import Foundation

extension Model {
    static func countSavedItemsWithoutLoading() -> Int {
        if brokenMode {
            log("Ignoring count, model is broken, app needs restart.")
            return 0
        }

        var count = 0
        var coordinationError: NSError?
        var loadingError: NSError?

        coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                return
            }

            do {
                let uuidFileURL = url.appendingPathComponent("uuids")
                do {
                    if let fileSize = try fm.attributesOfItem(atPath: uuidFileURL.path)[FileAttributeKey.size] as? UInt64 {
                        if fileSize % 16 != 0 {
                            log("Warning: uuid file size not multiple of 16!")
                        }
                        count = Int(fileSize / 16)
                    } else {
                        log("Could not parse the size of uuid file")
                    }
                } catch {
                    log("Loading Error: \(error)")
                    loadingError = error as NSError
                }
            }
        }

        if let e = loadingError ?? coordinationError {
            log("Error in counting saved items: \(e)")
        }

        return count
    }

    static func locateItemWithoutLoading(uuid: String) -> ArchivedItem? {
        if brokenMode {
            log("Ignoring locate operation, model is broken, app needs restart.")
            return nil
        }

        var item: ArchivedItem?
        var coordinationError: NSError?

        coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                return
            }

            let dataPath = url.appendingPathComponent(uuid)
            if let data = try? Data(contentsOf: dataPath) {
                item = try? loadDecoder.decode(ArchivedItem.self, from: data)
            }
        }

        if let e = coordinationError {
            log("Error in searching through saved items: \(e)")
        }

        return item
    }

    static func getLabelsWithoutLoading() -> Set<String> {
        if brokenMode {
            log("Ignoring locate operation, model is broken, app needs restart.")
            return []
        }

        var labels = Set<String>()
        iterateThroughSavedItemsWithoutLoading {
            labels.formUnion($0.labels)
            return true
        }

        return labels
    }

    static func locateComponentWithoutLoading(uuid: String) -> (ArchivedItem, Component)? {
        if brokenMode {
            log("Ignoring locate component operation, model is broken, app needs restart.")
            return nil
        }

        var result: (ArchivedItem, Component)?
        let uuidData = UUID(uuidString: uuid)

        iterateThroughSavedItemsWithoutLoading { item in
            if let component = item.components.first(where: { $0.uuid == uuidData }) {
                result = (item, component)
                return false
            }
            return true
        }
        return result
    }

    private static func iterateThroughSavedItemsWithoutLoading(perItemCallback: (ArchivedItem) -> Bool) {
        if brokenMode {
            log("Ignoring search operation, model is broken, app needs restart.")
            return
        }

        var coordinationError: NSError?
        var loadingError: NSError?

        coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

            if !FileManager.default.fileExists(atPath: url.path) {
                return
            }

            do {
                let decoder = loadDecoder
                let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
                d.withUnsafeBytes { pointer in
                    pointer.bindMemory(to: uuid_t.self).forEach { u in
                        autoreleasepool {
                            let u = UUID(uuid: u)
                            let dataPath = url.appendingPathComponent(u.uuidString)
                            if let data = try? Data(contentsOf: dataPath), let item = try? decoder.decode(ArchivedItem.self, from: data), !perItemCallback(item) {
                                return
                            }
                        }
                    }
                }
            } catch {
                log("Loading Error: \(error)")
                loadingError = error as NSError
            }
        }

        if let e = loadingError ?? coordinationError {
            log("Error in searching through saved items for a component: \(e)")
        }
    }

    static func insertNewItemsWithoutLoading(items: [ArchivedItem], addToDrops: Bool) {
        if items.isEmpty { return }

        if brokenMode {
            log("Ignoring insert operation, model is broken, app needs restart.")
            return
        }

        var closureError: NSError?
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
            do {
                let fm = FileManager.default
                var uuidData: Data
                if fm.fileExists(atPath: url.path) {
                    uuidData = try Data(contentsOf: url.appendingPathComponent("uuids"))
                } else {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                    uuidData = emptyData
                }

                let encoder = saveEncoder
                for item in items {
                    item.flags.remove(.isBeingCreatedBySync)
                    item.flags.remove(.needsSaving)
                    let u = item.uuid
                    let t = u.uuid
                    let finalPath = url.appendingPathComponent(u.uuidString)
                    try encoder.encode(item).write(to: finalPath)
                    uuidData.insert(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15], at: 0)
                }
                try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

            } catch {
                closureError = error as NSError
            }
            // do not update last modified date, as there may be external changes that need to be loaded additionally later as well
        }
        if let e = coordinationError ?? closureError {
            log("Error inserting new item into saved data store: \(e.localizedDescription)")
        } else if addToDrops {
            for item in items {
                Model.append(drop: item)
            }
        }
    }
}
