
import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

	private var relatedItem: FileProviderItem?

	private let uuid: String
	private let model: Model

	private var sortByDate = false
	private var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	private var oldItemIds2Items: Dictionary<NSFileProviderItemIdentifier, FileProviderItem>!

	init(relatedItem: FileProviderItem?, model: Model) { // nil is root
		self.relatedItem = relatedItem
		self.model = model
		uuid = relatedItem?.dropItem?.uuid.uuidString ?? relatedItem?.typeItem?.uuid.uuidString ?? "root"

		super.init()

		if relatedItem == nil {
			log("Enumerator created for root")
			oldItemIds2Items = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.itemIdentifier, $0) })
		} else if relatedItem?.dropItem == nil {
			log("Enumerator for \(uuid) created for type directory")
		} else {
			log("Enumerator for \(uuid) created for entity directory")
		}
	}

    func invalidate() {
    }

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {

		if relatedItem?.typeItem != nil {
			log("Listing file \(uuid)")
		} else if relatedItem?.dropItem != nil {
			log("Listing directory \(uuid)")
		} else {
			log("Listing root")
		}

		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name

		var items: [NSFileProviderItemProtocol]
		if let fileItem = relatedItem?.typeItem {
			items = [FileProviderItem(fileItem)]
		} else if let dirItem = relatedItem?.dropItem {
			items = getItems(for: dirItem)
		} else { // root or working set (same thing for us)
			items = rootItems
		}
		observer.didEnumerate(items)
		observer.finishEnumerating(upTo: nil)
    }

	private func getItems(for dirItem: ArchivedDropItem) -> [FileProviderItem] {
		if sortByDate {
			return dirItem.typeItems.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
		} else {
			return dirItem.typeItems.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
		}
	}

	private var rootItems: [FileProviderItem] {
		if sortByDate {
			return model.drops.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
		} else {
			return model.drops.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
		}
	}

	func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	deinit {
		log("Enumerator for \(uuid) shut down")
	}

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {

		model.reloadDataIfNeeded()

		if relatedItem?.typeItem != nil {
			log("Enumerate changes for file \(uuid), we never have any, will report no changes")

		} else if let dropItem = relatedItem?.dropItem {
			log("Enumerating changes for directory \(uuid)")

			let meAfter = rootItems.first { $0.dropItem?.uuid.uuidString == uuid }

			if let meAfter = meAfter { // I exist, have I changed?
				if dropItem.updatedAt != meAfter.dropItem?.updatedAt {
					relatedItem = meAfter
					observer.didUpdate([meAfter])
					incrementAnchor()
					oldItemIds2Items = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.itemIdentifier, $0) })
				}
			} else { // I'm gone
				var ids = [NSFileProviderItemIdentifier(uuid)]
				let childrenIds = dropItem.typeItems.map { NSFileProviderItemIdentifier($0.uuid.uuidString) }
				ids.append(contentsOf: childrenIds)
				observer.didDeleteItems(withIdentifiers: ids)
				incrementAnchor()
				oldItemIds2Items = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.itemIdentifier, $0) })
			}

		} else {
			log("Enumerating changes for root")

			let newItemIds2Items = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.itemIdentifier, $0) })

			let updatedItemIds2Items = newItemIds2Items.filter({ (id, newItem) -> Bool in
				let oldItem = oldItemIds2Items[id]
				return oldItem == nil || oldItem?.dropItem?.updatedAt != newItem.dropItem?.updatedAt
			})
			if updatedItemIds2Items.count > 0 {
				observer.didUpdate(Array(updatedItemIds2Items.values))
			}

			let deletedItemIds = oldItemIds2Items.keys.filter { !newItemIds2Items.keys.contains($0) }
			if deletedItemIds.count > 0 {
				observer.didDeleteItems(withIdentifiers: deletedItemIds)
			}

			if updatedItemIds2Items.count > 0 || deletedItemIds.count > 0 {
				incrementAnchor()
				oldItemIds2Items = newItemIds2Items
			}
		}

		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }

	private func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}
}
