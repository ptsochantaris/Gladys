import CoreSpotlight
import GladysCommon

final class IndexRequestHandler: CSIndexExtensionRequestHandler, IndexerItemProvider {
    private lazy var indexDelegate = Indexer(itemProvider: self)

    @MainActor
    func iterateThroughAllItems(perItem: (ArchivedItem) -> Bool) {
        LiteModel.iterateThroughSavedItemsWithoutLoading(perItemCallback: perItem)
    }

    @MainActor
    func getItem(uuid: String) -> ArchivedItem? {
        LiteModel.locateItemWithoutLoading(uuid: uuid)
    }

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        log("Reindexing all spotlight items…")
        defer {
            log("Reindexing all spotlight items done")
        }
        indexDelegate.searchableIndex(searchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler: acknowledgementHandler)
    }

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        log("Reindexing some spotlight items…")
        defer {
            log("Reindexing some spotlight items done")
        }
        indexDelegate.searchableIndex(searchableIndex, reindexSearchableItemsWithIdentifiers: identifiers, acknowledgementHandler: acknowledgementHandler)
    }

    override func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
        log("Serving data for a spotlight item…")
        defer {
            log("Serving data for a spotlight item done")
        }
        return try indexDelegate.data(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
    }

    override func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
        log("Providing URL for a spotlight item…")
        defer {
            log("Providing URL for a spotlight item done")
        }
        return try indexDelegate.fileURL(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier, inPlace: inPlace)
    }

    override func searchableIndexDidThrottle(_: CSSearchableIndex) {}

    override func searchableIndexDidFinishThrottle(_: CSSearchableIndex) {}
}
