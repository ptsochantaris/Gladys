
import FileProvider

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
		DispatchQueue.main.async {
			if page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) {
				log("Starting new set of pages sorted by date for \(self.uuid)")
				self.oldItemIds2Dates.removeAll()
			} else if page.rawValue == (NSFileProviderPage.initialPageSortedByName as Data) {
				log("Starting new set of pages sorted by name for \(self.uuid)")
				self.oldItemIds2Dates.removeAll()
			} else { // page
				log("Follow-up page for \(self.uuid)")
			}

			let (items, nextCursor) = self.getFileItems(from: page, length: 50)
			items.forEach { self.oldItemIds2Dates[$0.itemIdentifier] = $0.gladysModificationDate }
			observer.didEnumerate(items)
			observer.finishEnumerating(upTo: nextCursor)
		}
	}

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		DispatchQueue.main.async {
			log("Listing changes for \(self.uuid) from anchor: \(String(data: syncAnchor.rawValue, encoding: .utf8)!)")
			self.currentAnchor = syncAnchor
			let (items, _) = self.getFileItems(from: nil, length: nil)
			self.enumerateChanges(for: observer, with: items)
			items.forEach { self.oldItemIds2Dates[$0.itemIdentifier] = $0.gladysModificationDate }
			observer.finishEnumeratingChanges(upTo: self.currentAnchor, moreComing: false)
		}
	}

	private func enumerateChanges(for observer: NSFileProviderChangeObserver, with items: [FileProviderItem]) {

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

		let deletedItemIds = oldItemIds2Dates.keys.filter({ !newItemIds2Items.keys.contains($0) })
		if deletedItemIds.count > 0 {
			for id in deletedItemIds {
				oldItemIds2Dates[id] = nil
				log("Reporting deletion of item \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: deletedItemIds)
			incrementAnchor()
		}
	}

	func invalidate() {
		oldItemIds2Dates.removeAll()
		log("Enumerator for \(uuid) invalidated")
	}

	func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderItem], NSFileProviderPage?) {
		return ([], nil)
	}

	@objc func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	private func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}
}
