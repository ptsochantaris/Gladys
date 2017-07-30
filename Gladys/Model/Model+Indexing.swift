
import CoreSpotlight

extension Model: CSSearchableIndexDelegate {

	func reIndex(items: [ArchivedDropItem], completion: @escaping ()->Void) {

		let group = DispatchGroup()
		for _ in 0 ..< items.count {
			group.enter()
		}

		let bgQueue = DispatchQueue.global(qos: .background)
		bgQueue.async {
			for item in items {
				item.makeIndex { success in
					group.leave() // re-index completion
				}
			}
		}
		group.notify(queue: bgQueue) {
			completion()
		}
	}

	func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
		let existingItems = drops
		CSSearchableIndex.default().deleteAllSearchableItems { error in
			if let error = error {
				log("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
			}
			self.reIndex(items: existingItems, completion: acknowledgementHandler)
		}
	}

	func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
		let existingItems = drops.filter { identifiers.contains($0.uuid.uuidString) }
		let currentItemIds = drops.map { $0.uuid.uuidString }
		let deletedItems = identifiers.filter { currentItemIds.contains($0) }
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: deletedItems) { error in
			if let error = error {
				log("Warning: Error while deleting non-existing item from index: \(error.localizedDescription)")
			}
			self.reIndex(items: existingItems, completion: acknowledgementHandler)
		}
	}

	func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
		if let item = drops.filter({ $0.uuid.uuidString == itemIdentifier }).first, let data = item.bytes(for: typeIdentifier) {
			return data
		}
		return Data()
	}

	func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
		if let item = drops.filter({ $0.uuid.uuidString == itemIdentifier }).first, let url = item.url(for: typeIdentifier) {
			return url as URL
		}
		return URL(string:"file://")!
	}
}

