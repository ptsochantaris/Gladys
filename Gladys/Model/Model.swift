
import Foundation
import CoreSpotlight

#if MAINAPP
import FileProvider
#endif

final class Model: NSObject, CSSearchableIndexDelegate {

	var drops: [ArchivedDropItem]

	private let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .inherit, target: nil)

	static var storageRoot: URL {
		let docs = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.build.bru.Gladys")!
		return docs.appendingPathComponent("File Provider Storage", isDirectory: true)
	}

	static var fileUrl: URL {
		return storageRoot.appendingPathComponent("items.json")
	}

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
				let data = try Data(contentsOf: url)
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
	#endif

	//////////////////

	private func reIndex(items: [ArchivedDropItem], completion: @escaping ()->Void) {

		let group = DispatchGroup()
		group.enter()

		let bgQueue = DispatchQueue.global(qos: .background)
		bgQueue.async {
			let identifiers = items.map { $0.uuid.uuidString }
			CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
				for item in items {
					group.enter()
					item.makeIndex { success in
						group.leave() // re-index completion
					}
				}
				group.leave() // delete completion
			}
		}
		group.notify(queue: bgQueue) {
			completion()
		}
	}

	func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
		reIndex(items: drops, completion: acknowledgementHandler)
	}

	func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
		let items = drops.filter { identifiers.contains($0.uuid.uuidString) }
		reIndex(items: items, completion: acknowledgementHandler)
	}

	func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
		let model = Model()
		if let item = model.drops.filter({ $0.uuid.uuidString == itemIdentifier }).first,
			let data = item.bytes(for: typeIdentifier) {

			return data
		}
		return Data()
	}

	func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
		let model = Model()
		if let item = model.drops.filter({ $0.uuid.uuidString == itemIdentifier }).first,
			let url = item.url(for: typeIdentifier) {
			return url as URL
		}
		return URL(string:"file://")!
	}

	var sizeInBytes: Int64 {
		return drops.reduce(0, { $0 + $1.sizeInBytes })
	}

	///////////////////////

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
}

