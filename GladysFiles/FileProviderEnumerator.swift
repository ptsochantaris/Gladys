
import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    var enumeratedItemIdentifier: NSFileProviderItemIdentifier
	private let relatedItem: FileProviderItem?
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
		relatedItem = FileProviderExtension.getItem(for: enumeratedItemIdentifier)

		if enumeratedItemIdentifier == NSFileProviderItemIdentifier.rootContainer {
			currentAnchor = "0"
		}
        super.init()
    }

    func invalidate() {
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAtPage page: Data) {

		let p = NSFileProviderPage(data: page)
		sortByDate = p == NSFileProviderInitialPageSortedByDate // otherwise by name

		var items: [NSFileProviderItemProtocol]
		if let fileItem = relatedItem?.typeItem {
			items = [FileProviderItem(fileItem)]
		} else if let dirItem = relatedItem?.item {
			if sortByDate {
				items = dirItem.typeItems.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
			} else {
				items = dirItem.typeItems.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
			}
		} else { // root or all dirs (same thing for us)
			items = rootItems
		}
		observer.didEnumerate(items)
		observer.finishEnumerating(upToPage: page)
    }

	private var rootItems: [FileProviderItem] {
		if sortByDate {
			return FileProviderExtension.model.drops.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
		} else {
			return FileProviderExtension.model.drops.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
		}
	}

	private var sortByDate = false
	private var currentAnchor: String?

	func currentSyncAnchor(completionHandler: @escaping (Data?) -> Void) {
		completionHandler(currentAnchor?.data(using: .utf8))
	}
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, fromSyncAnchor anchor: Data) {
		if enumeratedItemIdentifier == NSFileProviderItemIdentifier.rootContainer {

			let oldItemIds = rootItems.map { $0.itemIdentifier }
			FileProviderExtension.model.reloadData()
			let newItems = rootItems
			let newItemIds = rootItems.map { $0.itemIdentifier }

			let createdItems = newItems.filter { !oldItemIds.contains($0.itemIdentifier) }
			observer.didUpdate(createdItems)

			let deletedItemIds = oldItemIds.filter({ !newItemIds.contains($0) })
			observer.didDeleteItems(withIdentifiers: deletedItemIds)
		} else if relatedItem?.typeItem != nil {
			NSLog("Changes requested for enumerator of end-file")
		} else if relatedItem?.item != nil {
			NSLog("Changes requested for enumerator of directory")
		}

		let oldAnchorString = String(data: anchor, encoding: .utf8) ?? "0"
		let newAnchorString = String((Int64(oldAnchorString) ?? 0) + 1)
		currentAnchor = newAnchorString
		let newAnchorData = newAnchorString.data(using: .utf8) ?? anchor
		observer.finishEnumeratingChanges(upTo: newAnchorData, moreComing: false)
    }
    
}
