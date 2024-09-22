#if !os(watchOS)
    import CoreSpotlight
    import Foundation

    extension CSSearchableIndex: @retroactive @unchecked Sendable {}
    extension CSSearchableItem: @retroactive @unchecked Sendable {}

    public protocol IndexerItemProvider: AnyObject {
        @MainActor
        func iterateThroughAllItems(perItem: @escaping @MainActor (ArchivedItem) async -> Void) async

        @MainActor
        func getItem(uuid: String) -> ArchivedItem?
    }

    @MainActor
    public final class Indexer: NSObject, CSSearchableIndexDelegate, Sendable {
        private weak var itemProvider: IndexerItemProvider!

        public init(itemProvider: IndexerItemProvider) {
            self.itemProvider = itemProvider
            super.init()
            log("Indexer initialised")
        }

        deinit {
            log("Indexer disposed")
        }

        public nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
            nonisolated(unsafe) let handler = acknowledgementHandler
            Task { @MainActor in
                do {
                    log("Clearing items before full reindex")
                    try await searchableIndex.deleteAllSearchableItems()
                } catch {
                    log("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
                }
                var searchableItems = [CSSearchableItem]()
                await itemProvider.iterateThroughAllItems { item in
                    searchableItems.append(item.searchableItem)
                    if searchableItems.count > 99 {
                        await Self.indexBlock(of: searchableItems, in: searchableIndex)
                        searchableItems.removeAll()
                    }
                }
                if searchableItems.isPopulated {
                    await Self.indexBlock(of: searchableItems, in: searchableIndex)
                    searchableItems.removeAll()
                }
                log("Indexing done")
                handler()
            }
        }

        public nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
            nonisolated(unsafe) let handler = acknowledgementHandler
            Task { @MainActor in
                let identifierSet = Set(identifiers)
                var searchableItems = [CSSearchableItem]()
                await itemProvider.iterateThroughAllItems { item in
                    if identifierSet.contains(item.uuid.uuidString) {
                        searchableItems.append(item.searchableItem)
                        if searchableItems.count > 99 {
                            await Self.indexBlock(of: searchableItems, in: searchableIndex)
                            searchableItems.removeAll()
                        }
                    }
                }
                if searchableItems.isPopulated {
                    await Self.indexBlock(of: searchableItems, in: searchableIndex)
                    searchableItems.removeAll()
                }
                log("Indexing done")
                handler()
            }
        }

        private static func indexBlock(of items: [CSSearchableItem], in index: CSSearchableIndex) async {
            log("Submitting block for indexing")
            do {
                try await index.indexSearchableItems(items)
                log("Block indexed")
            } catch {
                log("Error while indexing: \(error.localizedDescription)")
            }
        }

        public nonisolated func data(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
            try data(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
        }

        public nonisolated func fileURL(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace _: Bool) throws -> URL {
            try fileURL(itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
        }

        public nonisolated func reIndex(items: [CSSearchableItem], in index: CSSearchableIndex) async {
            do {
                try await index.indexSearchableItems(items)
                log("\(items.count) item(s) indexed")
            } catch {
                log("Error indexing items: \(error.localizedDescription)")
            }
        }

        private nonisolated func data(itemIdentifier: String, typeIdentifier: String) throws -> Data {
            onlyOnMainThread {
                if let item = itemProvider.getItem(uuid: itemIdentifier),
                   let data = item.bytes(for: typeIdentifier) {
                    return data
                }
                return Data()
            }
        }

        private nonisolated func fileURL(itemIdentifier: String, typeIdentifier: String) throws -> URL {
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
