import AppKit
import GladysCommon
import GladysUI
import UniformTypeIdentifiers

extension Model {
    static func registerStateHandler() {
        stateHandler = { state in
            switch state {
            case .migrated, .willSave:
                break

            case .startupComplete:
                break

            case let .saveComplete(dueToSyncFetch):
                Task {
                    do {
                        if try await shouldSync(dueToSyncFetch: dueToSyncFetch) {
                            try await CloudManager.syncAfterSaveIfNeeded()
                        }
                    } catch {
                        log("Error in sync after save: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private static var eventMonitor: FileMonitor?

    static func startMonitoringForExternalChangesToBlobs() {
        syncWithExternalUpdates()

        eventMonitor = FileMonitor(directory: appStorageUrl) { url in
            let components = url.pathComponents
            let count = components.count
            guard count > 3, components[count - 4].hasSuffix(".MacGladys"),
                  let potentialParentUUID = UUID(uuidString: String(components[count - 3])),
                  let potentialComponentUUID = UUID(uuidString: String(components[count - 2]))
            else {
                return
            }

            Task { @MainActor in
                guard let parent = DropStore.item(uuid: potentialParentUUID),
                      parent.eligibleForExternalUpdateCheck,
                      let component = ComponentLookup.shared.component(uuid: potentialParentUUID),
                      component.scanForBlobChanges()
                else { return }

                parent.needsReIngest = true
                parent.markUpdated()
                log("Detected a modified component blob, uuid \(potentialComponentUUID), will re-ingest parent")
                await parent.reIngest()
            }
        }
    }

    private static func syncWithExternalUpdates() {
        let changedDrops = DropStore.allDrops.filter { $0.scanForBlobChanges() }
        for item in changedDrops {
            log("Located item whose data has been externally changed: \(item.uuid.uuidString)")
            item.needsReIngest = true
            item.markUpdated()
            Task {
                await item.reIngest()
            }
        }
    }

    @discardableResult
    static func addItems(from pasteBoard: NSPasteboard, at indexPath: IndexPath, overrides: ImportOverrides?, filterContext: Filter?) -> PasteResult {
        guard let pasteboardItems = pasteBoard.pasteboardItems else { return .noData }

        let importGroup = DispatchGroup()

        let itemProviders = pasteboardItems.compactMap { pasteboardItem -> NSItemProvider? in
            let extractor = NSItemProvider()
            var count = 0
            let utis = Set(pasteboardItem.types.map(\.rawValue))

            if let filePromises = pasteBoard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] {
                for promise in filePromises {
                    guard let promiseType = promise.fileTypes.first, !promise.fileNames.isEmpty else {
                        continue
                    }
                    if utis.contains(promiseType) { // No need to fetch the file, the data exists as a solid block in the pasteboard
                        continue
                    }
                    count += 1
                    importGroup.enter()

                    // log("Waiting for promise: \(promiseType)")
                    promise.receivePromisedFiles(atDestination: temporaryDirectoryUrl, options: [:], operationQueue: OperationQueue()) { url, error in
                        // log("Completed promise: \(promiseType)")
                        if let error {
                            log("Warning, loading error in file drop: \(error.localizedDescription)")
                        } else {
                            let dropData = try? Data(contentsOf: url)
                            extractor.registerDataRepresentation(forTypeIdentifier: promiseType, visibility: .all) { callback -> Progress? in
                                callback(dropData, nil)
                                return nil
                            }
                        }
                        importGroup.leave()
                    }
                }
            }

            for type in pasteboardItem.types {
                count += 1
                extractor.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { callback -> Progress? in
                    let data = pasteboardItem.data(forType: type)
                    callback(data, nil)
                    return nil
                }
            }
            return count > 0 ? extractor : nil
        }

        importGroup.wait()

        if itemProviders.isEmpty {
            return .noData
        }

        return addItems(itemProviders: itemProviders, indexPath: indexPath, overrides: overrides, filterContext: filterContext)
    }

    @discardableResult
    @MainActor
    static func addItems(itemProviders: [NSItemProvider], indexPath: IndexPath, overrides: ImportOverrides?, filterContext: Filter?) -> PasteResult {
        var archivedItems = [ArchivedItem]()
        for provider in itemProviders {
            for newItem in ArchivedItem.importData(providers: [provider], overrides: overrides) {
                var modelIndex = indexPath.item
                if let filterContext, filterContext.isFiltering {
                    modelIndex = filterContext.nearestUnfilteredIndexForFilteredIndex(indexPath.item, checkForWeirdness: false)
                    if filterContext.isFilteringLabels, !PersistedOptions.dontAutoLabelNewItems {
                        newItem.labels = filterContext.enabledLabelsForItems
                    }
                }
                DropStore.insert(drop: newItem, at: modelIndex)
                archivedItems.append(newItem)
            }
        }

        if archivedItems.isEmpty {
            return .noData
        }
        allFilters.forEach {
            $0.update(signalUpdate: .animated)
        }
        return .success(archivedItems)
    }

    @MainActor
    static func importFiles(paths: [String], filterContext: Filter?) {
        let providers = paths.compactMap { path -> NSItemProvider? in
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                return NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
            } else {
                return NSItemProvider(contentsOf: url)
            }
        }
        _ = addItems(itemProviders: providers, indexPath: IndexPath(item: 0, section: 0), overrides: nil, filterContext: filterContext)
    }

    nonisolated static func unsafeModificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
