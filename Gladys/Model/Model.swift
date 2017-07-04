import Foundation

#if FILEPROVIDER || ACTIONEXTENSION || MAINAPP
	import FileProvider
#endif

#if ACTIONEXTENSION || MAINAPP || INDEXER
	import CoreSpotlight
#endif

#if MAINAPP
	import UIKit
#endif

final class Model: NSObject {

	var drops: [ArchivedDropItem]

	static var appStorageUrl: URL = {
		#if FILEPROVIDER
			return NSFileProviderManager.default.documentStorageURL
		#else
			return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.build.bru.Gladys")!.appendingPathComponent("File Provider Storage")
		#endif
	}()

	static var fileUrl: URL = {
		return appStorageUrl.appendingPathComponent("items.json")
	}()

	override init() {
		drops = Model.loadData() ?? [ArchivedDropItem]()
		super.init()

		#if MAINAPP
			Model.filePresenter.model = self

			let n = NotificationCenter.default
			n.addObserver(self, selector: #selector(foregrounded), name: .UIApplicationWillEnterForeground, object: nil)
			n.addObserver(self, selector: #selector(backgrounded), name: .UIApplicationDidEnterBackground, object: nil)
			foregrounded()
		#endif
	}

	private static var coordinator: NSFileCoordinator {
		#if MAINAPP
			return NSFileCoordinator(filePresenter: filePresenter)
		#else
			let coordinator = NSFileCoordinator(filePresenter: nil)
			coordinator.purposeIdentifier = Bundle.main.bundleIdentifier!
			return coordinator
		#endif
	}

	private static var dataFileLastModified = Date.distantPast
	private static func loadData() -> [ArchivedDropItem]? {
		
		var res: [ArchivedDropItem]?

		var coordinationError: NSError?
		coordinator.coordinate(readingItemAt: Model.fileUrl, options: .withoutChanges, error: &coordinationError) { url in

			if FileManager.default.fileExists(atPath: url.path) {
				do {

					var shouldLoad = true
					if let dataModified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date {
						if dataModified == dataFileLastModified {
							shouldLoad = false
						} else {
							dataFileLastModified = dataModified
						}
					}
					if shouldLoad {
						log("Needed to reload data")
						let data = try Data(contentsOf: url, options: [.alwaysMapped])
						res = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
					}
				} catch {
					log("Loading Error: \(error)")
				}
			} else {
				log("Starting fresh store")
			}
		}
		if let e = coordinationError {
			log("Error in loading coordination: \(e.localizedDescription)")
		}
		return res
	}

	func reloadDataIfNeeded() {
		if let d = Model.loadData() {
			drops = d
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
		}
	}

	#if ACTIONEXTENSION || MAINAPP

	private let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	func save(completion: ((Bool)->Void)? = nil) {

		let start = Date()

		let itemsToSave = drops.filter { !$0.isLoading && !$0.isDeleting }

		#if MAINAPP
			log("Starting save queue background task")
			let bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.saveTask", expirationHandler: nil)
		#endif

		saveQueue.async {

			do {
				let data = try JSONEncoder().encode(itemsToSave)
				self.coordinatedSave(data: data)
				log("Saved: \(-start.timeIntervalSinceNow) seconds")
				if let completion = completion {
					OperationQueue.main.addOperation {
						completion(true)
					}
				}

			} catch {
				log("Saving Error: \(error.localizedDescription)")
				if let completion = completion {
					OperationQueue.main.addOperation {
						completion(false)
					}
				}
			}
			#if MAINAPP
				OperationQueue.main.addOperation {
					NotificationCenter.default.post(name: .SaveComplete, object: nil)
					DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
						log("Ending save queue background task")
						UIApplication.shared.endBackgroundTask(bgTask)
					}
				}
			#endif
		}
	}

	private func coordinatedSave(data: Data) {
		var coordinationError: NSError?
		Model.coordinator.coordinate(writingItemAt: Model.fileUrl, options: .forReplacing, error: &coordinationError) { url in
			try! data.write(to: url, options: [])
			if let dataModified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date {
				Model.dataFileLastModified = dataModified
			}
		}
		if let e = coordinationError {
			log("Error in saving coordination: \(e.localizedDescription)")
		}

		NSFileProviderManager.default.signalEnumerator(forContainerItemIdentifier: NSFileProviderItemIdentifier.rootContainer) { error in
			if let e = error {
				log("Error signalling change to file provider: \(e.localizedDescription)")
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
					OperationQueue.main.addOperation {
						let uuids = items.map { $0.uniqueIdentifier }
						let items = self.drops.filter { uuids.contains($0.uuid.uuidString) }
						self._cachedFilteredDrops?.append(contentsOf: items)
						NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
					}
				}
				q.completionHandler = { error in
					if let error = error {
						log("Search error: \(error.localizedDescription)")
					}
					OperationQueue.main.addOperation {
						if self._cachedFilteredDrops?.isEmpty ?? true {
							NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
						}
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

	////////////////////////////

	#if MAINAPP

		private static let filePresenter = ModelFilePresenter()

		@objc private func foregrounded() {
			reloadDataIfNeeded()
			NSFileCoordinator.addFilePresenter(Model.filePresenter)
		}

		@objc private func backgrounded() {
			NSFileCoordinator.removeFilePresenter(Model.filePresenter)
		}

		deinit {
			backgrounded()
		}

		private class ModelFilePresenter: NSObject, NSFilePresenter {

			weak var model: Model?

			var presentedItemURL: URL? {
				return Model.fileUrl
			}

			var presentedItemOperationQueue: OperationQueue {
				return OperationQueue.main
			}

			func presentedItemDidChange() {
				model?.reloadDataIfNeeded()
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
					log("Warning: Error while deleting all items for re-index: \(error.localizedDescription)")
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
					log("Warning: Error while deleting non-existing item from index: \(error.localizedDescription)")
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

