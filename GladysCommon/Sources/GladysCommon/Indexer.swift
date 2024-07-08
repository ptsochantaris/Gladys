#if !os(watchOS)
    import CoreSpotlight
    import Foundation

    public protocol IndexerItemProvider: AnyObject {
        @MainActor
        func iterateThroughAllItems(perItem: (ArchivedItem) -> Bool)

        @MainActor
        func getItem(uuid: String) -> ArchivedItem?
    }

    public final class Indexer: NSObject, CSSearchableIndexDelegate {
        private weak var itemProvider: IndexerItemProvider!

        public init(itemProvider: IndexerItemProvider) {
            self.itemProvider = itemProvider
            super.init()
            log("Indexer initialised")
        }

        deinit {
            log("Indexer disposed")
        }

        public func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
            Task { @MainActor in
                do {
                    log("Clearing items before full reindex")
                    try await searchableIndex.deleteAllSearchableItems()
                } catch {
                    log("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
                }
                var searchableItems = [CSSearchableItem]()
                itemProvider.iterateThroughAllItems { item in
                    searchableItems.append(item.searchableItem)
                    if searchableItems.count > 99 {
                        log("Submitting block for indexing")
                        searchableIndex.indexSearchableItems(searchableItems) { error in
                            if let error {
                                log("Error while indexing: \(error.localizedDescription)")
                            } else {
                                log("Block indexed")
                            }
                        }
                        searchableItems.removeAll()
                    }
                    return true
                }
                if searchableItems.isPopulated {
                    do {
                        try await searchableIndex.indexSearchableItems(searchableItems)
                        log("Last block indexed")
                    } catch {
                        log("Error while indexing: \(error.localizedDescription)")
                    }
                    searchableItems.removeAll()
                }
                log("Indexing done")
                acknowledgementHandler()
            }
        }

        public func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
            Task { @MainActor in
                let identifierSet = Set(identifiers)
                var searchableItems = [CSSearchableItem]()
                itemProvider.iterateThroughAllItems { item in
                    if identifierSet.contains(item.uuid.uuidString) {
                        searchableItems.append(item.searchableItem)
                        if searchableItems.count > 99 {
                            log("Submitting block for indexing")
                            searchableIndex.indexSearchableItems(searchableItems) { error in
                                if let error {
                                    log("Error while indexing: \(error.localizedDescription)")
                                } else {
                                    log("Last block indexed")
                                }
                            }
                            searchableItems.removeAll()
                        }
                    }
                    return true
                }
                if searchableItems.isPopulated {
                    do {
                        try await searchableIndex.indexSearchableItems(searchableItems)
                        log("Block indexed")
                    } catch {
                        log("Error while indexing: \(error.localizedDescription)")
                    }
                    searchableItems.removeAll()
                }
                log("Indexing done")
                acknowledgementHandler()
            }
        }

        public func data(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
            try data(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
        }

        public func fileURL(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace _: Bool) throws -> URL {
            try fileURL(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
        }

        public func reIndex(items: [CSSearchableItem], in index: CSSearchableIndex) async {
            do {
                try await index.indexSearchableItems(items)
                log("\(items.count) item(s) indexed")
            } catch {
                log("Error indexing items: \(error.localizedDescription)")
            }
        }

        private func data(itemIdentifier: String, typeIdentifier: String) throws -> Data {
            onlyOnMainThread {
                if let item = itemProvider.getItem(uuid: itemIdentifier),
                   let data = item.bytes(for: typeIdentifier) {
                    return data
                }
                return Data()
            }
        }

        private func fileURL(itemIdentifier: String, typeIdentifier: String) throws -> URL {
            onlyOnMainThread {
                if let item = itemProvider.getItem(uuid: itemIdentifier),
                   let url = item.url(for: typeIdentifier) {
                    return url as URL
                }
                return URL(string: "file://")!
            }
        }
    }
#endif
