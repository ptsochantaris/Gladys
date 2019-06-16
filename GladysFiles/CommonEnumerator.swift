
import FileProvider

protocol FileProviderConvertible {
	var uuid: UUID { get }
	var asFileProviderItem: FileProviderItem { get }
}

extension ArchivedDropItem: FileProviderConvertible {
	var asFileProviderItem: FileProviderItem {
		return FileProviderItem(self)
	}
}

extension ArchivedDropItemType: FileProviderConvertible {
	var asFileProviderItem: FileProviderItem {
		return FileProviderItem(self)
	}
}

class CommonEnumerator: NSObject, NSFileProviderEnumerator {

	let uuid: String

	private var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	private var oldItemIds2Dates = [NSFileProviderItemIdentifier: Date]()

	init(uuid: String) {
		self.uuid = uuid
		super.init()
		log("Enumerator for \(uuid) started")
	}

	deinit {
		log("Enumerator for \(uuid) shut down")
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		if page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) {
			log("Starting new set of pages sorted by date for \(uuid)")
			oldItemIds2Dates.removeAll()
		} else if page.rawValue == (NSFileProviderPage.initialPageSortedByName as Data) {
			log("Starting new set of pages sorted by name for \(uuid)")
			oldItemIds2Dates.removeAll()
		} else { // page
			log("Follow-up page for \(uuid)")
		}

		let (drops, nextCursor) = getFileItems(from: page, length: 100)
		let items = drops.map { $0.asFileProviderItem }
		items.forEach { oldItemIds2Dates[$0.itemIdentifier] = $0.gladysModificationDate }
		observer.didEnumerate(items)
		observer.finishEnumerating(upTo: nextCursor)
	}

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		log("Listing changes for \(uuid) from anchor: \(String(data: syncAnchor.rawValue, encoding: .utf8)!)")
		currentAnchor = syncAnchor
		let (drops, _) = getFileItems(from: nil, length: nil)
		let items = drops.map { $0.asFileProviderItem }
		let newItemIds2Items = Dictionary(uniqueKeysWithValues: items.map { ($0.itemIdentifier, $0) })

		let updatedItemIds2Items = newItemIds2Items.filter { id, newItem -> Bool in
			let oldDate = oldItemIds2Dates[id]
			return oldDate == nil || oldDate != newItem.gladysModificationDate
		}

		if updatedItemIds2Items.count > 0 {
			for id in updatedItemIds2Items.keys {
				log("Reporting update of item \(id.rawValue)")
			}
			observer.didUpdate(Array(updatedItemIds2Items.values))
			incrementAnchor()
		}

		let deletedItemIds = oldItemIds2Dates.keys.filter { !newItemIds2Items.keys.contains($0) }
		if deletedItemIds.count > 0 {
			for id in deletedItemIds {
				oldItemIds2Dates[id] = nil
				log("Reporting deletion of item \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: deletedItemIds)
			incrementAnchor()
		}

		items.forEach { oldItemIds2Dates[$0.itemIdentifier] = $0.gladysModificationDate }
		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
	}

	func invalidate() {
		oldItemIds2Dates.removeAll()
		log("Enumerator for \(uuid) invalidated")
	}

	func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderConvertible], NSFileProviderPage?) {
		return ([], nil)
	}

	func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	private func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}
}
