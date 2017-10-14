
import FileProvider

class CommonEnumerator: NSObject, NSFileProviderEnumerator {

	var sortByDate = false

	let uuid: String

	private var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	private var oldItemIds2Dates: Dictionary<NSFileProviderItemIdentifier, Date>!

	private func refreshCurrentDates() {
		oldItemIds2Dates = Dictionary(uniqueKeysWithValues: fileItems.map { ($0.itemIdentifier, $0.contentModificationDate ?? .distantPast) })
	}

	init(uuid: String) {
		self.uuid = uuid
		super.init()
		refreshCurrentDates()
		log("Enumerator for \(uuid) started")
	}

	@objc(enumerateItemsForObserver:startingAtPage:)
	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		modelAccessQueue.async {
			self.sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name
			log("Listing \(self.uuid)")
			observer.didEnumerate(self.fileItems)
			observer.finishEnumerating(upTo: nil)
		}
	}

	@objc(enumerateChangesForObserver:fromSyncAnchor:)
	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		modelAccessQueue.async {
			log("Listing changes for \(self.uuid) from anchor: \(String(data: syncAnchor.rawValue, encoding: .utf8)!)")
			self.currentAnchor = syncAnchor
			self.enumerateChanges(for: observer)
			observer.finishEnumeratingChanges(upTo: self.currentAnchor, moreComing: false)
		}
	}

	private func enumerateChanges(for observer: NSFileProviderChangeObserver) {

		let newItemIds2Items = Dictionary(uniqueKeysWithValues: fileItems.map { ($0.itemIdentifier, $0) })

		let updatedItemIds2Items = newItemIds2Items.filter { id, newItem -> Bool in
			let oldDate = oldItemIds2Dates![id]
			return oldDate == nil || oldDate != newItem.contentModificationDate
		}
		if updatedItemIds2Items.count > 0 {
			for id in updatedItemIds2Items.keys {
				log("Reporting update of item \(id.rawValue)")
			}
			observer.didUpdate(Array(updatedItemIds2Items.values))
			incrementAnchor()
		}

		let deletedItemIds = oldItemIds2Dates!.keys.filter { !newItemIds2Items.keys.contains($0) }
		if deletedItemIds.count > 0 {
			for id in deletedItemIds {
				log("Reporting deletion of item \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: deletedItemIds)
			incrementAnchor()
		}

		refreshCurrentDates()
	}

	var fileItems: [FileProviderItem] {
		return []
	}

	@objc func invalidate() {
	}

	@objc func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	private func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}

	deinit {
		log("Enumerator for \(uuid) shut down")
	}
}
