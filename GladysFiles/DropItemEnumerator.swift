
import FileProvider

final class DropItemEnumerator: CommonEnumerator, NSFileProviderEnumerator {

	private var children: [ArchivedDropItemType]

	init(dropItem: ArchivedDropItem) {
		children = dropItem.typeItems
		super.init(uuid: dropItem.uuid.uuidString)
		log("Enumerator for \(uuid) created for item directory")
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		modelAccessQueue.async {
			self._enumerateItems(for: observer, startingAt: page)
		}
	}
	private func _enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name
		log("Listing directory \(uuid)")

		let items: [FileProviderItem]
		if sortByDate {
			items = children.sorted { $0.updatedAt < $1.updatedAt }.map { FileProviderItem($0) }
		} else {
			items = children.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
		observer.didEnumerate(items)
		observer.finishEnumerating(upTo: nil)
    }

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		modelAccessQueue.async {
			self._enumerateChanges(for: observer, from: syncAnchor)
		}
	}
	
	private func _enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		log("Listing changes for directory \(uuid) from anchor: \(String(data: syncAnchor.rawValue, encoding: .utf8)!)")
		currentAnchor = syncAnchor

		let newDropItem = model.drops.first { $0.uuid.uuidString == uuid }

		if let newDropItem = newDropItem { // I exist, have I changed?
			var updatedItems = [FileProviderItem]()
			let newChildren = newDropItem.typeItems
			for newTypeItem in newChildren {
				if let previousTypeItem = children.first(where: { $0.uuid == newTypeItem.uuid }), previousTypeItem.updatedAt != newTypeItem.updatedAt {
					updatedItems.append(FileProviderItem(newTypeItem))
				}
			}
			children = newChildren
			if updatedItems.count > 0 {
				for item in updatedItems {
					log("Signalling update of type item \(item.itemIdentifier.rawValue)")
				}
				observer.didUpdate(updatedItems)
				incrementAnchor()
			}

		} else { // I'm gone
			var ids = [NSFileProviderItemIdentifier(uuid)]
			let childrenIds = children.map { NSFileProviderItemIdentifier($0.uuid.uuidString) }
			ids.append(contentsOf: childrenIds)
			for id in ids {
				log("Signalling deletion of item \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: ids)
			incrementAnchor()
		}

		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }
}
