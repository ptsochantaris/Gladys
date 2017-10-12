
import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

	private var dropItem: ArchivedDropItem?

	private let uuid: String
	private let model: Model

	private var sortByDate = false
	private var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	private var oldItemIds2Items: Dictionary<NSFileProviderItemIdentifier, FileProviderItem>?

	init(dropItem: ArchivedDropItem?, model: Model) { // nil is root
		self.dropItem = dropItem
		self.model = model
		uuid = dropItem?.uuid.uuidString ?? "root"

		super.init()

		if dropItem == nil {
			log("Enumerator created for root")
			oldItemIds2Items = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.itemIdentifier, $0) })
		} else {
			log("Enumerator for \(uuid) created for item directory")
		}
	}

	func invalidate() {
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {

		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name

		let items: [FileProviderItem]
		if let dirItem = dropItem {
			log("Listing directory \(uuid)")
			if sortByDate {
				items = dirItem.typeItems.sorted { $0.updatedAt < $1.updatedAt }.map { FileProviderItem($0) }
			} else {
				items = dirItem.typeItems.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
			}

		} else { // root or working set (same thing for us)
			log("Listing root")
			items = rootItems
		}
		observer.didEnumerate(items)
		observer.finishEnumerating(upTo: nil)
    }

	private var rootItems: [FileProviderItem] {
		if sortByDate {
			return model.drops.sorted { $0.createdAt < $1.createdAt }.map { FileProviderItem($0) }
		} else {
			return model.drops.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
	}

	func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	deinit {
		log("Enumerator for \(uuid) shut down")
	}

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {

		func incrementAnchor() {
			let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
			currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
		}

		model.reloadDataIfNeeded()

		if let d = dropItem {
			//log("Enumerating changes for directory \(uuid)")

			let meAfter = rootItems.first { $0.dropItem?.uuid.uuidString == uuid }

			if let meAfter = meAfter, let newDropItem = meAfter.dropItem { // I exist, have I changed?
				var updatedItems = [FileProviderItem]()
				for newTypeItem in newDropItem.typeItems {
					if let previousTypeItem = dropItem?.typeItems.first(where: { $0.uuid == newTypeItem.uuid }), previousTypeItem.modifiedInFiles || previousTypeItem.updatedAt != newTypeItem.updatedAt {
						updatedItems.append(FileProviderItem(newTypeItem))
						newTypeItem.modifiedInFiles = false
					}
				}
				dropItem = newDropItem
				if updatedItems.count > 0 {
					for item in updatedItems {
						log("Signalling update of item \(item.itemIdentifier.rawValue)")
					}
					observer.didUpdate(updatedItems)
					incrementAnchor()
				}

			} else { // I'm gone
				var ids = [NSFileProviderItemIdentifier(uuid)]
				let childrenIds = d.typeItems.map { NSFileProviderItemIdentifier($0.uuid.uuidString) }
				ids.append(contentsOf: childrenIds)
				for id in ids {
					log("Signalling deletion of item \(id.rawValue)")
				}
				observer.didDeleteItems(withIdentifiers: ids)
				incrementAnchor()
			}

		} else {
			//log("Enumerating changes for root")

			let newItemIds2Items = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.itemIdentifier, $0) })

			let updatedItemIds2Items = newItemIds2Items.filter { id, newItem -> Bool in
				let oldItem = oldItemIds2Items![id]
				return oldItem == nil || oldItem?.dropItem?.updatedAt != newItem.dropItem?.updatedAt
			}
			if updatedItemIds2Items.count > 0 {
				for id in updatedItemIds2Items.keys {
					log("Signalling update of directory \(id.rawValue)")
				}
				observer.didUpdate(Array(updatedItemIds2Items.values))
			}

			let deletedItemIds = oldItemIds2Items!.keys.filter { !newItemIds2Items.keys.contains($0) }
			if deletedItemIds.count > 0 {
				for id in deletedItemIds {
					log("Signalling deletion of directory \(id.rawValue)")
				}
				observer.didDeleteItems(withIdentifiers: deletedItemIds)
			}

			if updatedItemIds2Items.count > 0 || deletedItemIds.count > 0 {
				incrementAnchor()
				oldItemIds2Items = newItemIds2Items
			}
		}

		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }
}
