#if canImport(AppKit)
    import AppKit
    import Foundation
    import GladysCommon
    import GladysUI

    extension Model {
        @discardableResult
        static func addItems(itemProviders: [DataImporter], indexPath: IndexPath, overrides: ImportOverrides?, filterContext: Filter?) -> PasteResult {
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

            sendNotification(name: .FiltersShouldUpdate)

            return .success(archivedItems)
        }

        @discardableResult
        static func addItems(from pasteBoard: NSPasteboard, at indexPath: IndexPath, overrides: ImportOverrides?, filterContext: Filter?) -> PasteResult {
            guard let pasteboardItems = pasteBoard.pasteboardItems else { return .noData }

            let importGroup = DispatchGroup()

            let importers = pasteboardItems.compactMap { pasteboardItem -> [DataImporter] in
                var importers = [DataImporter]()
                let utis = Set<String>(pasteboardItem.types.map(\.rawValue))

                if let filePromises = pasteBoard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] {
                    for promise in filePromises {
                        guard let promiseType = promise.fileTypes.first, promise.fileNames.isPopulated else {
                            continue
                        }
                        if utis.contains(promiseType) { // No need to fetch the file, the data exists as a solid block in the pasteboard
                            continue
                        }
                        importGroup.enter()

                        // log("Waiting for promise: \(promiseType)")
                        promise.receivePromisedFiles(atDestination: temporaryDirectoryUrl, options: [:], operationQueue: OperationQueue()) { url, error in
                            // log("Completed promise: \(promiseType)")
                            if let error {
                                log("Warning, loading error in file drop: \(error.localizedDescription)")
                            } else {
                                if let dropData = try? Data(contentsOf: url) {
                                    let importer = DataImporter(type: promiseType, data: dropData, suggestedName: nil)
                                    importers.append(importer)
                                }
                            }
                            importGroup.leave()
                        }
                    }
                }

                let importer = DataImporter(pasteboardItem: pasteboardItem, suggestedName: nil)
                importers.append(importer)
                return importers
            }

            importGroup.wait()

            if importers.isEmpty {
                return .noData
            }

            let flatList = importers.flatMap { $0 }
            return addItems(itemProviders: flatList, indexPath: indexPath, overrides: overrides, filterContext: filterContext)
        }
    }
#endif
