#if !os(watchOS)
    import CoreSpotlight
    import Foundation

    extension CSSearchableIndex: @retroactive @unchecked Sendable {}
    extension CSSearchableItem: @retroactive @unchecked Sendable {}

    public protocol IndexerItemProvider: AnyObject {
        func iterateThroughItems(perItem: @escaping @Sendable @MainActor (ArchivedItem) async -> Bool) async
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
            nonisolated(unsafe) let handler = acknowledgementHandler
            nonisolated(unsafe) let i = itemProvider!
            Task { @MainActor in // needed explicitly
                do {
                    log("Clearing items before full reindex")
                    try await searchableIndex.deleteAllSearchableItems()
                } catch {
                    log("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
                }
                var searchableItems = [CSSearchableItem]()
                await i.iterateThroughItems { item in
                    searchableItems.append(item.searchableItem)
                    if searchableItems.count > 99 {
                        await Self.indexBlock(of: searchableItems, in: searchableIndex)
                        searchableItems.removeAll()
                    }
                    return true
                }
                if searchableItems.isPopulated {
                    await Self.indexBlock(of: searchableItems, in: searchableIndex)
                    searchableItems.removeAll()
                }
                log("Indexing done")
                handler()
            }
        }

        public func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
            nonisolated(unsafe) let handler = acknowledgementHandler
            nonisolated(unsafe) let i = itemProvider!
            Task { @MainActor in // needed explicitly
                let identifierSet = Set(identifiers)
                var searchableItems = [CSSearchableItem]()
                await i.iterateThroughItems { item in
                    if identifierSet.contains(item.uuid.uuidString) {
                        searchableItems.append(item.searchableItem)
                        if searchableItems.count > 99 {
                            await Self.indexBlock(of: searchableItems, in: searchableIndex)
                            searchableItems.removeAll()
                        }
                    }
                    return true
                }
                if searchableItems.isPopulated {
                    await Self.indexBlock(of: searchableItems, in: searchableIndex)
                    searchableItems.removeAll()
                }
                log("Indexing done")
                handler()
            }
        }

        @concurrent private static func indexBlock(of items: [CSSearchableItem], in index: CSSearchableIndex) async {
            log("Submitting block for indexing")
            do {
                try await index.indexSearchableItems(items)
                log("Block indexed")
            } catch {
                log("Error while indexing: \(error.localizedDescription)")
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
            if let item = itemProvider.getItem(uuid: itemIdentifier),
               let data = onlyOnMainThread({ item.bytes(for: typeIdentifier) }) {
                return data
            }
            return Data()
        }

        private func fileURL(itemIdentifier: String, typeIdentifier: String) throws -> URL {
            if let item = itemProvider.getItem(uuid: itemIdentifier),
               let url = onlyOnMainThread({ item.url(for: typeIdentifier) }) {
                return url as URL
            }
            return URL(string: "file://")!
        }
    }
#endif
