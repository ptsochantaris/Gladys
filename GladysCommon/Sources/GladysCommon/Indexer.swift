#if !os(watchOS)
    import CoreSpotlight
    import Foundation

    public final class Indexer: NSObject, CSSearchableIndexDelegate {
        override public init() {
            super.init()
            log("Indexer initialised")
        }

        deinit {
            log("Indexer disposed")
        }

        public func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
            Task { @MainActor in
                do {
                    try await searchableIndex.deleteAllSearchableItems()
                } catch {
                    log("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
                }
                var searchableItems = [CSSearchableItem]()
                LiteModel.iterateThroughSavedItemsWithoutLoading { item in
                    searchableItems.append(item.searchableItem)
                    if searchableItems.count > 99 {
                        reIndex(items: searchableItems, in: searchableIndex)
                        searchableItems.removeAll()
                    }
                    return true
                }
                if !searchableItems.isEmpty {
                    reIndex(items: searchableItems, in: searchableIndex)
                }
                acknowledgementHandler()
            }
        }

        public func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
            Task { @MainActor in
                let identifierSet = Set(identifiers)
                var searchableItems = [CSSearchableItem]()
                LiteModel.iterateThroughSavedItemsWithoutLoading { item in
                    if identifierSet.contains(item.uuid.uuidString) {
                        searchableItems.append(item.searchableItem)
                        if searchableItems.count > 99 {
                            reIndex(items: searchableItems, in: searchableIndex)
                            searchableItems.removeAll()
                        }
                    }
                    return true
                }
                if !searchableItems.isEmpty {
                    reIndex(items: searchableItems, in: searchableIndex)
                }
                acknowledgementHandler()
            }
        }

        @MainActor // lie, but taking care of that in the method
        public func data(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
            if Thread.isMainThread {
                return try data(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
            } else {
                return try DispatchQueue.main.sync {
                    try data(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
                }
            }
        }

        @MainActor // lie, but taking care of that in the method
        public func fileURL(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace _: Bool) throws -> URL {
            if Thread.isMainThread {
                return try fileURL(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
            } else {
                return try DispatchQueue.main.sync {
                    try fileURL(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
                }
            }
        }

        public func reIndex(items: [CSSearchableItem], in index: CSSearchableIndex) {
            index.indexSearchableItems(items) { error in
                if let error {
                    log("Error indexing items: \(error.localizedDescription)")
                } else {
                    log("\(items.count) item(s) indexed")
                }
            }
        }

        @MainActor
        private func data(itemIdentifier: String, typeIdentifier: String) throws -> Data {
            if let item = LiteModel.locateItemWithoutLoading(uuid: itemIdentifier), let data = item.bytes(for: typeIdentifier) {
                return data
            }
            return Data()
        }

        @MainActor
        private func fileURL(itemIdentifier: String, typeIdentifier: String) throws -> URL {
            if let item = LiteModel.locateItemWithoutLoading(uuid: itemIdentifier), let url = item.url(for: typeIdentifier) {
                return url as URL
            }
            return URL(string: "file://")!
        }
    }
#endif
