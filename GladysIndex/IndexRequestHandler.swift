import CoreSpotlight
import GladysCommon

final class IndexRequestHandler: CSIndexExtensionRequestHandler, IndexerItemProvider {
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
        let indexer = Indexer(itemProvider: self)
        indexer.searchableIndex(searchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler: acknowledgementHandler)
    }

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        log("Reindexing some spotlight items…")
        let indexer = Indexer(itemProvider: self)
        indexer.searchableIndex(searchableIndex, reindexSearchableItemsWithIdentifiers: identifiers, acknowledgementHandler: acknowledgementHandler)
    }

    override func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
        log("Serving data for a spotlight item…")
        let indexer = Indexer(itemProvider: self)
        return try indexer.data(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
    }

    override func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
        log("Providing URL for a spotlight item…")
        let indexer = Indexer(itemProvider: self)
        return try indexer.fileURL(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier, inPlace: inPlace)
    }

    override func searchableIndexDidThrottle(_: CSSearchableIndex) {}

    override func searchableIndexDidFinishThrottle(_: CSSearchableIndex) {}
}
