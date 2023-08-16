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
        Task { @MainActor in
            indexDelegate.searchableIndex(searchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler: acknowledgementHandler)
        }
    }

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        Task { @MainActor in
            indexDelegate.searchableIndex(searchableIndex, reindexSearchableItemsWithIdentifiers: identifiers, acknowledgementHandler: acknowledgementHandler)
        }
    }

    @MainActor
    override func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
        try indexDelegate.data(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
    }

    @MainActor
    override func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
        try indexDelegate.fileURL(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier, inPlace: inPlace)
    }
}
