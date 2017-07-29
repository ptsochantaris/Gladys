
import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

	private let relatedItem: FileProviderItem?

	private let uuid: String
	private let model: Model

	private var sortByDate = false
	private var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	init(relatedItem: FileProviderItem?, model: Model) { // nil is root
		self.relatedItem = relatedItem
		self.model = model
		uuid = relatedItem?.dropItem?.uuid.uuidString ?? relatedItem?.dropItem?.uuid.uuidString ?? "root"

		super.init()
		if relatedItem == nil {
			log("Enumerator created for root")
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
			log("Listing file")
		} else if relatedItem?.dropItem != nil {
			log("Listing entity directory")
		} else {
			log("Listing root")
		}

		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name

		var items: [NSFileProviderItemProtocol]
		if let fileItem = relatedItem?.typeItem {
			items = [FileProviderItem(fileItem)]
		} else if let dirItem = relatedItem?.dropItem {
			items = getItems(for: dirItem)
		} else { // root or all dirs (same thing for us)
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
		if relatedItem?.typeItem != nil {
			log("Changes requested for enumerator of end-file, we never have any")

		} else if relatedItem?.dropItem != nil {
			log("Changes requested for enumerator of directory")

			model.reloadDataIfNeeded()
			let newItemIds = rootItems.map { $0.itemIdentifier }
			let myId = NSFileProviderItemIdentifier(uuid)

			if !newItemIds.contains(myId) { // I'm gone
				var ids = [myId]
				if let childrenIds = relatedItem?.dropItem?.typeItems.map({ NSFileProviderItemIdentifier($0.uuid.uuidString) }) {
					ids.append(contentsOf: childrenIds)
					observer.didDeleteItems(withIdentifiers: ids)
					incrementAnchor()
				}
			}

		} else {
			log("Enumerating changes for root")

			let oldItemIds = rootItems.map { $0.itemIdentifier }
			model.reloadDataIfNeeded()
			let newItems = rootItems
			let newItemIds = rootItems.map { $0.itemIdentifier }

			let createdItems = newItems.filter { !oldItemIds.contains($0.itemIdentifier) }
			if createdItems.count > 0 {
				observer.didUpdate(createdItems)
			}

			let deletedItemIds = oldItemIds.filter({ !newItemIds.contains($0) })
			if deletedItemIds.count > 0 {
				observer.didDeleteItems(withIdentifiers: deletedItemIds)
			}

			if createdItems.count > 0 || deletedItemIds.count > 0 {
				incrementAnchor()
			}
		}

		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }

	private func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}
}
