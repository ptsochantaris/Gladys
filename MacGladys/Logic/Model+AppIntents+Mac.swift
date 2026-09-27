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

            let filePromises = pasteBoard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
            var requestedPromises = Set<ObjectIdentifier>()
            var promisedImports = [Task<[DataImporter], Never>]()
            var importers = [DataImporter]()

            for pasteboardItem in pasteboardItems {
                let utis = Set<String>(pasteboardItem.types.map(\.rawValue))

                for promise in filePromises {
                    guard let promiseType = promise.fileTypes.first, promise.fileNames.isPopulated else {
                        continue
                    }
                    if utis.contains(promiseType) { // No need to fetch the file, the data exists as a solid block in the pasteboard
                        continue
                    }
                    if requestedPromises.insert(ObjectIdentifier(promise)).inserted {
                        // Must be requested now, while the drag or paste is still in progress
                        promisedImports.append(receivePromisedFiles(from: promise, type: promiseType))
                    }
                }

                importers.append(DataImporter(pasteboardItem: pasteboardItem, suggestedName: nil))
            }

            if promisedImports.isPopulated {
                // Promised files arrive asynchronously, so they are added as they complete rather than blocking the main thread
                Task {
                    for promisedImport in promisedImports {
                        let promisedImporters = await promisedImport.value
                        if promisedImporters.isPopulated {
                            addItems(itemProviders: promisedImporters, indexPath: indexPath, overrides: overrides, filterContext: filterContext)
                        }
                    }
                }
            }

            if importers.isEmpty {
                return .noData
            }

            return addItems(itemProviders: importers, indexPath: indexPath, overrides: overrides, filterContext: filterContext)
        }

        private static func receivePromisedFiles(from promise: NSFilePromiseReceiver, type promiseType: String) -> Task<[DataImporter], Never> {
            let expectedCount = promise.fileNames.count
            let (fileData, continuation) = AsyncStream.makeStream(of: Data?.self)

            // The reader is called once per promised file, on a background queue, so it must only touch the Sendable continuation
            promise.receivePromisedFiles(atDestination: temporaryDirectoryUrl, options: [:], operationQueue: OperationQueue()) { @Sendable url, error in
                if let error {
                    log("Warning, loading error in file drop: \(error.localizedDescription)")
                    continuation.yield(nil)
                } else {
                    continuation.yield(try? Data(contentsOf: url))
                }
            }

            return Task {
                var importers = [DataImporter]()
                var receivedCount = 0
                for await data in fileData {
                    if let data {
                        importers.append(DataImporter(type: promiseType, data: data, suggestedName: nil))
                    }
                    receivedCount += 1
                    if receivedCount == expectedCount {
                        break
                    }
                }
                return importers
            }
        }
    }
#endif
