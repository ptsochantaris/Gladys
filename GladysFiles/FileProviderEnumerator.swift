
import FileProvider

let modelAccessQueue = DispatchQueue(label: "build.bru.Gladys.fileprovider.model.queue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

class CommonEnumerator: NSObject {
	fileprivate let uuid: String
	fileprivate let model: Model

	fileprivate var sortByDate = false
	fileprivate var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	init(model: Model, uuid: String) {
		self.model = model
		self.uuid = uuid
		super.init()
	}

	@objc func invalidate() {
	}

	@objc func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}

	deinit {
		log("Enumerator for \(uuid) shut down")
	}
}

final class RootEnumerator: CommonEnumerator, NSFileProviderEnumerator {

	private var oldItemIds2Dates: Dictionary<NSFileProviderItemIdentifier, Date>!

	init(model: Model) {
		super.init(model: model, uuid: "root")
		log("Enumerator created for root")
		refreshCurrentDates()
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		modelAccessQueue.async {
			self._enumerateItems(for: observer, startingAt: page)
		}
	}
	func _enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name
		log("Listing root")
		model.reloadDataIfNeeded()
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
	func _enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		log("Listing changes for root")
		model.reloadDataIfNeeded()

		let newItemIds2Items = Dictionary(uniqueKeysWithValues: dirItems.map { ($0.itemIdentifier, $0) })

		let updatedItemIds2Items = newItemIds2Items.filter { id, newItem -> Bool in
			let oldDate = oldItemIds2Dates![id]
			return oldDate == nil || oldDate != newItem.contentModificationDate
		}
		if updatedItemIds2Items.count > 0 {
			for id in updatedItemIds2Items.keys {
				log("Signalling update of directory \(id.rawValue)")
			}
			observer.didUpdate(Array(updatedItemIds2Items.values))
		}

		let deletedItemIds = oldItemIds2Dates!.keys.filter { !newItemIds2Items.keys.contains($0) }
		if deletedItemIds.count > 0 {
			for id in deletedItemIds {
				log("Signalling deletion of directory \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: deletedItemIds)
		}

		refreshCurrentDates()

		incrementAnchor()
		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
	}

	private func refreshCurrentDates() {
		oldItemIds2Dates = Dictionary(uniqueKeysWithValues: dirItems.map { ($0.itemIdentifier, $0.contentModificationDate ?? .distantPast) })
	}
}

final class DirectoryEnumerator: CommonEnumerator, NSFileProviderEnumerator {

	private var children: [ArchivedDropItemType]

	init(dropItem: ArchivedDropItem, model: Model) { // nil is root
		children = dropItem.typeItems
		super.init(model: model, uuid: dropItem.uuid.uuidString)
		log("Enumerator for \(uuid) created for item directory")
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		modelAccessQueue.async {
			self._enumerateItems(for: observer, startingAt: page)
		}
	}
	func _enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		sortByDate = page.rawValue == (NSFileProviderPage.initialPageSortedByDate as Data) // otherwise by name
		log("Listing directory \(uuid)")
		model.reloadDataIfNeeded()

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
	func _enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		log("Listing changes for directory \(uuid)")
		model.reloadDataIfNeeded()

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
					log("Signalling update of item \(item.itemIdentifier.rawValue)")
				}
				observer.didUpdate(updatedItems)
			}

		} else { // I'm gone
			var ids = [NSFileProviderItemIdentifier(uuid)]
			let childrenIds = children.map { NSFileProviderItemIdentifier($0.uuid.uuidString) }
			ids.append(contentsOf: childrenIds)
			for id in ids {
				log("Signalling deletion of item \(id.rawValue)")
			}
			observer.didDeleteItems(withIdentifiers: ids)
		}

		incrementAnchor()
		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }
}
