
import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

	private let relatedItem: FileProviderItem?

	private let uuid: String

	private var sortByDate = false
	private var currentAnchor = "0".data(using: .utf8)!

	init(relatedItem: FileProviderItem?) { // nil is root
		self.relatedItem = relatedItem
		uuid = relatedItem?.item?.uuid.uuidString ?? relatedItem?.item?.uuid.uuidString ?? "root"

		super.init()
		if relatedItem == nil {
			NSLog("Enumerator created for root")
		} else if relatedItem?.item == nil {
			NSLog("Enumerator for \(uuid) created for type directory")
		} else {
			NSLog("Enumerator for \(uuid) created for entity directory")
		}
	}

    func invalidate() {
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAtPage page: Data) {

		if relatedItem?.typeItem != nil {
			NSLog("Listing file (wat?)")
		} else if relatedItem?.item != nil {
			NSLog("Listing entity directory")
		} else {
			NSLog("Listing root")
		}

		let p = NSFileProviderPage(data: page)
		sortByDate = p == NSFileProviderInitialPageSortedByDate // otherwise by name

		var items: [NSFileProviderItemProtocol]
		if let fileItem = relatedItem?.typeItem {
			items = [FileProviderItem(fileItem)]
		} else if let dirItem = relatedItem?.item {
			items = getItems(for: dirItem)
		} else { // root or all dirs (same thing for us)
			items = rootItems
		}
		observer.didEnumerate(items)
		observer.finishEnumerating(upToPage: nil)
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
			return FileProviderExtension.model.drops.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
		} else {
			return FileProviderExtension.model.drops.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
		}
	}

	func currentSyncAnchor(completionHandler: @escaping (Data?) -> Void) {
		completionHandler(currentAnchor)
	}

	deinit {
		NSLog("Enumerator for \(uuid) shut down")
	}
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, fromSyncAnchor anchor: Data) {
		if relatedItem?.typeItem != nil {
			NSLog("Changes requested for enumerator of end-file")

		} else if relatedItem?.item != nil {
			NSLog("Changes requested for enumerator of directory")

			FileProviderExtension.model.reloadData()
			let newItemIds = rootItems.map { $0.itemIdentifier }
			let myId = NSFileProviderItemIdentifier(uuid)

			if !newItemIds.contains(myId) { // I'm gone
				var ids = [myId]
				if let childrenIds = relatedItem?.item?.typeItems.map({ NSFileProviderItemIdentifier($0.uuid.uuidString) }) {
					ids.append(contentsOf: childrenIds)
					observer.didDeleteItems(withIdentifiers: ids)
					incrementAnchor()
				}
			}

		} else {
			NSLog("Enumerating changes for root")

			let oldItemIds = rootItems.map { $0.itemIdentifier }
			FileProviderExtension.model.reloadData()
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
		let newAnchorCount = Int64(String(data: currentAnchor, encoding: .utf8)!)! + 1
		currentAnchor = String(newAnchorCount).data(using: .utf8)!
	}
}
