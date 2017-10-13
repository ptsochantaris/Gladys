
import FileProvider

final class RootEnumerator: CommonEnumerator, NSFileProviderEnumerator {

	private var oldItemIds2Dates: Dictionary<NSFileProviderItemIdentifier, Date>!

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.rootContainer.rawValue)
		log("Enumerator created for root")
		refreshCurrentDates()
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		modelAccessQueue.async {
			self._enumerateItems(for: observer, startingAt: page)
		}
	}
	private func _enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name
		log("Listing root")
		observer.didEnumerate(dirItems)
		observer.finishEnumerating(upTo: nil)
	}

	private var dirItems: [FileProviderItem] {
		if sortByDate {
			return model.drops.sorted { $0.createdAt < $1.createdAt }.map { FileProviderItem($0) }
		} else {
			return model.drops.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
	}

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		modelAccessQueue.async {
			self._enumerateChanges(for: observer, from: syncAnchor)
		}
	}
	
	private func _enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		log("Listing changes for root from anchor: \(String(data: syncAnchor.rawValue, encoding: .utf8)!)")
		currentAnchor = syncAnchor

		let newItemIds2Items = Dictionary(uniqueKeysWithValues: dirItems.map { ($0.itemIdentifier, $0) })

		let updatedItemIds2Items = newItemIds2Items.filter { id, newItem -> Bool in
			let oldDate = oldItemIds2Dates![id]
			return oldDate == nil || oldDate != newItem.contentModificationDate
		}
		if updatedItemIds2Items.count > 0 {
			for id in updatedItemIds2Items.keys {
				log("Signalling update of item \(id.rawValue)")
			}
			observer.didUpdate(Array(updatedItemIds2Items.values))
			incrementAnchor()
		}

		let deletedItemIds = oldItemIds2Dates!.keys.filter { !newItemIds2Items.keys.contains($0) }
		if deletedItemIds.count > 0 {
			for id in deletedItemIds {
				log("Signalling deletion of item \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: deletedItemIds)
			incrementAnchor()
		}

		refreshCurrentDates()

		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
	}

	private func refreshCurrentDates() {
		oldItemIds2Dates = Dictionary(uniqueKeysWithValues: dirItems.map { ($0.itemIdentifier, $0.contentModificationDate ?? .distantPast) })
	}
}
