
import CoreSpotlight

extension Model {

	private final class IndexProxy: NSObject, CSSearchableIndexDelegate {
		func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
			Model.searchableIndex(searchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler: acknowledgementHandler)
		}

		func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
			Model.searchableIndex(searchableIndex, reindexSearchableItemsWithIdentifiers: identifiers, acknowledgementHandler: acknowledgementHandler)
		}

		func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
			return try Model.data(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
		}

		func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
			return try Model.fileURL(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier, inPlace: inPlace)
		}
	}

    private static let indexDelegate = IndexProxy()

    static func setupIndexDelegate() {
        CSSearchableIndex.default().indexDelegate = indexDelegate
    }
    
	static func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        let items = drops.map { $0.searchableItem }
		searchableIndex.deleteAllSearchableItems { error in
			if let error = error {
				log("Warning: Error while deleting all items for re-index: \(error.finalDescription)")
			}
            reIndex(items: items, in: searchableIndex, completion: acknowledgementHandler)
		}
	}

	static func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        let existingItems = drops.filter { identifiers.contains($0.uuid.uuidString) }.map { $0.searchableItem }
        reIndex(items: existingItems, in: searchableIndex, completion: acknowledgementHandler)
	}

	static func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
		if let item = drops.filter({ $0.uuid.uuidString == itemIdentifier }).first, let data = item.bytes(for: typeIdentifier) {
			return data
		}
		return Data()
	}

	static func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
		if let item = drops.filter({ $0.uuid.uuidString == itemIdentifier }).first, let url = item.url(for: typeIdentifier) {
			return url as URL
		}
		return URL(string:"file://")!
	}
}

