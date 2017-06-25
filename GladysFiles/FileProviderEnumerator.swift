
import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    var enumeratedItemIdentifier: NSFileProviderItemIdentifier?
	private let relatedItem: FileProviderItem?
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier?) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
		if let enumeratedItemIdentifier = enumeratedItemIdentifier {
			relatedItem = FileProviderExtension.getItem(for: enumeratedItemIdentifier)
		} else {
			relatedItem = nil
		}
        super.init()
    }

    func invalidate() {
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAtPage page: Data) {

		let p = NSFileProviderPage(data: page)
		let sortByDate = p == NSFileProviderInitialPageSortedByDate // otherwise by name

		var items: [NSFileProviderItemProtocol]
		if let fileItem = relatedItem?.typeItem {
			items = [FileProviderItem(fileItem)]
		} else if let dirItem = relatedItem?.item {
			if sortByDate {
				items = dirItem.typeItems.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
			} else {
				items = dirItem.typeItems.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
			}
		} else { // root or all dirs (same thing)
			if sortByDate {
				items = FileProviderExtension.model.drops.sorted(by: { $0.createdAt < $1.createdAt }).map { FileProviderItem($0) }
			} else {
				items = FileProviderExtension.model.drops.sorted(by: { $0.oneTitle < $1.oneTitle }).map { FileProviderItem($0) }
			}
		}
		observer.didEnumerate(items)
		observer.finishEnumerating(upToPage: nil)
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, fromSyncAnchor anchor: Data) {
		observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }
    
}
