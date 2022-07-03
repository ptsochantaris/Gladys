import CoreSpotlight

extension Model {
    private final class IndexProxy: NSObject, CSSearchableIndexDelegate {
        @MainActor
        func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
            Model.searchableIndex(searchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler: acknowledgementHandler)
        }

        @MainActor
        func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
            Model.searchableIndex(searchableIndex, reindexSearchableItemsWithIdentifiers: identifiers, acknowledgementHandler: acknowledgementHandler)
        }

        @MainActor
        func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
            try Model.data(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
        }

        @MainActor
        func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
            try Model.fileURL(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier, inPlace: inPlace)
        }
    }

    private static let indexDelegate = IndexProxy()

    static func setupIndexDelegate() {
        CSSearchableIndex.default().indexDelegate = indexDelegate
    }

    static func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        let items = drops.map(\.searchableItem)
        searchableIndex.deleteAllSearchableItems { error in
            if let error = error {
                log("Warning: Error while deleting all items for re-index: \(error.finalDescription)")
            }
            reIndex(items: items, in: searchableIndex, completion: acknowledgementHandler)
        }
    }

    static func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        let existingItems = drops.filter { identifiers.contains($0.uuid.uuidString) }.map(\.searchableItem)
        reIndex(items: existingItems, in: searchableIndex, completion: acknowledgementHandler)
    }

    static func data(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
        if let item = Model.item(uuid: itemIdentifier), let data = item.bytes(for: typeIdentifier) {
            return data
        }
        return emptyData
    }

    static func fileURL(for _: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace _: Bool) throws -> URL {
        if let item = Model.item(uuid: itemIdentifier), let url = item.url(for: typeIdentifier) {
            return url as URL
        }
        return URL(string: "file://")!
    }

    static func reIndex(items: [CSSearchableItem], in index: CSSearchableIndex, completion: (() -> Void)? = nil) {
        index.indexSearchableItems(items) { error in
            if let error = error {
                log("Error indexing items: \(error.finalDescription)")
            } else {
                log("\(items.count) item(s) indexed")
            }
            if let c = completion {
                DispatchQueue.main.async {
                    c()
                }
            }
        }
    }
}
