
import Foundation
import CoreSpotlight
import FileProvider

final class Model: NSObject {

	var drops: [ArchivedDropItem]

	static var fileUrl: URL = {
		return NSFileProviderManager.default.documentStorageURL.appendingPathComponent("items.json")
	}()

	override init() {
		drops = Model.loadData() ?? [ArchivedDropItem]()
		super.init()
	}

	private static var dataFileLastModified = Date.distantPast
	private static func loadData() -> [ArchivedDropItem]? {
		let url = Model.fileUrl
		if FileManager.default.fileExists(atPath: url.path) {
			do {

				if let dataModified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date {
					if dataModified <= dataFileLastModified {
						NSLog("No changes, no need to reload data")
						return nil
					}
					dataFileLastModified = dataModified
				}
				let data = try Data(contentsOf: url, options: [.alwaysMapped])
				NSLog("Loaded data")
				return try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)

			} catch {
				NSLog("Loading Error: \(error)")
			}
		} else {
			NSLog("Starting fresh store")
		}
		return nil
	}

	func reloadData() {
		NSLog("Reloading data")
		if let d = Model.loadData() {
			drops = d
		}
	}

	#if MAINAPP

	private let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .inherit, target: nil)

	func save(completion: ((Bool)->Void)? = nil) {

		let itemsToSave = drops.filter { !$0.isLoading && !$0.isDeleting }

		saveQueue.async {

			do {
				let data = try JSONEncoder().encode(itemsToSave)
				try data.write(to: Model.fileUrl, options: .atomic)
				DispatchQueue.main.async {
					NSLog("Saved")
					completion?(true)
					NotificationCenter.default.post(name: .SaveComplete, object: nil)
					NSFileProviderManager.default.signalEnumerator(forContainerItemIdentifier: NSFileProviderItemIdentifier.rootContainer) { error in
						if let e = error {
							NSLog("Error signalling change: \(e.localizedDescription)")
						}
					}
				}
			} catch {
				NSLog("Saving Error: \(error.localizedDescription)")
				if let completion = completion {
					DispatchQueue.main.async {
						completion(false)
					}
				}
			}
		}
	}

	var sizeInBytes: Int64 {
		return drops.reduce(0, { $0 + $1.sizeInBytes })
	}

	////////////////////////// Filtering

	var isFiltering: Bool {
		return _currentFilterQuery != nil
	}

	var filter: String? {
		didSet {

			guard filter != oldValue else {
				return
			}

			_currentFilterQuery?.cancel()

			if let f = filter, !f.isEmpty {
				_cachedFilteredDrops = []
				let criterion = "\"*\(f)*\"cd"
				let q = CSSearchQuery(queryString: "title == \(criterion) || contentDescription == \(criterion)", attributes: nil)
				q.foundItemsHandler = { items in
					DispatchQueue.main.async {
						let uuids = items.map { $0.uniqueIdentifier }
						let items = self.drops.filter { uuids.contains($0.uuid.uuidString) }
						self._cachedFilteredDrops?.append(contentsOf: items)
						NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
					}
				}
				_currentFilterQuery = q
				q.start()
			} else {
				_cachedFilteredDrops = nil
				_currentFilterQuery = nil
				NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
			}
		}
	}
	private var _currentFilterQuery: CSSearchQuery?
	private var _cachedFilteredDrops: [ArchivedDropItem]?
	var filteredDrops: [ArchivedDropItem] {
		if let f = _cachedFilteredDrops {
			return f
		} else {
			return drops
		}
	}

	#endif
}

//////////////////

#if MAINAPP || INDEXER

	extension Model: CSSearchableIndexDelegate {

		private func reIndex(items: [ArchivedDropItem], completion: @escaping ()->Void) {

			let group = DispatchGroup()
			for _ in 0 ..< items.count {
				group.enter()
			}

			let bgQueue = DispatchQueue.global(qos: .background)
			bgQueue.async {
				for item in items {
					item.makeIndex { success in
						group.leave() // re-index completion
					}
				}
			}
			group.notify(queue: bgQueue) {
				completion()
			}
		}
		
		func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
			let existingItems = drops
			CSSearchableIndex.default().deleteAllSearchableItems { error in
				if let error = error {
					NSLog("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
				}
				self.reIndex(items: existingItems, completion: acknowledgementHandler)
			}
		}

		func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
			let existingItems = drops.filter { identifiers.contains($0.uuid.uuidString) }
			let currentItemIds = drops.map { $0.uuid.uuidString }
			let deletedItems = identifiers.filter { currentItemIds.contains($0) }
			CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: deletedItems) { error in
				if let error = error {
					NSLog("Warning: Error while deleting non-existing item from index: \(error.localizedDescription)")
				}
				self.reIndex(items: existingItems, completion: acknowledgementHandler)
			}
		}

		func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
			if let item = drops.filter({ $0.uuid.uuidString == itemIdentifier }).first, let data = item.bytes(for: typeIdentifier) {
				return data
			}
			return Data()
		}

		func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
			if let item = drops.filter({ $0.uuid.uuidString == itemIdentifier }).first, let url = item.url(for: typeIdentifier) {
				return url as URL
			}
			return URL(string:"file://")!
		}
	}

#endif

