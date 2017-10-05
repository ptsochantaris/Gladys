
import CoreSpotlight
import UIKit

extension Model {
	
	private static var modelFilter: String?
	private static var currentFilterQuery: CSSearchQuery?
	private static var cachedFilteredDrops: [ArchivedDropItem]?

	private static var saveOverlap = 0
	private static var saveBgTask: UIBackgroundTaskIdentifier?
	
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: filePresenter)
	}

	func prepareToSave() {
		Model.saveOverlap += 1
		if Model.saveBgTask == nil {
			log("Starting save queue background task")
			Model.saveBgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.saveTask", expirationHandler: nil)
		}
	}

	func startupComplete() {

		// cleanup, in case of previous crashes, cancelled transfers, etc

		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(at: Model.appStorageUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else { return }
		let uuids = items.flatMap { UUID(uuidString: $0.lastPathComponent) }
		let nonExistingUUIDs = uuids.filter { uuid -> Bool in
			for d in drops {
				if d.uuid == uuid {
					return false
				}
			}
			return true
		}
		for uuid in nonExistingUUIDs {
			let url = Model.appStorageUrl.appendingPathComponent(uuid.uuidString)
			try? fm.removeItem(at: url)
		}
	}

	func saveDone() {
		Model.saveOverlap -= 1
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
			if Model.saveOverlap == 0, let b = Model.saveBgTask {
				log("Ending save queue background task")
				UIApplication.shared.endBackgroundTask(b)
				Model.saveBgTask = nil
			}
		}
	}

	func saveComplete() {
		NotificationCenter.default.post(name: .SaveComplete, object: nil)
	}
	
	func beginMonitoringChanges() {
		Model.filePresenter.model = self
		
		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(foregrounded), name: .UIApplicationWillEnterForeground, object: nil)
		n.addObserver(self, selector: #selector(backgrounded), name: .UIApplicationDidEnterBackground, object: nil)
		foregrounded()
	}
	
	var sizeInBytes: Int64 {
		return drops.reduce(0, { $0 + $1.sizeInBytes })
	}
	
	////////////////////////// Filtering
	
	var isFiltering: Bool {
		return Model.currentFilterQuery != nil
	}
	
	var filter: String? {
		get {
			return Model.modelFilter
		}
		set {
			guard Model.modelFilter != newValue else {
				return
			}
			
			Model.currentFilterQuery?.cancel()
			Model.modelFilter = newValue
			
			if let f = filter, !f.isEmpty {
				Model.cachedFilteredDrops = []
				let criterion = "\"*\(f)*\"cd"
				let q = CSSearchQuery(queryString: "title == \(criterion) || contentDescription == \(criterion)", attributes: nil)
				q.foundItemsHandler = { items in
					DispatchQueue.main.async {
						let uuids = items.map { $0.uniqueIdentifier }
						let items = self.drops.filter { uuids.contains($0.uuid.uuidString) }
						Model.cachedFilteredDrops?.append(contentsOf: items)
						NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
					}
				}
				q.completionHandler = { error in
					if let error = error {
						log("Search error: \(error.localizedDescription)")
					}
					DispatchQueue.main.async {
						if Model.cachedFilteredDrops?.isEmpty ?? true {
							NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
						}
					}
				}
				Model.currentFilterQuery = q
				q.start()
			} else {
				Model.cachedFilteredDrops = nil
				Model.currentFilterQuery = nil
				NotificationCenter.default.post(name: .SearchResultsUpdated, object: nil)
			}
		}
	}
	var filteredDrops: [ArchivedDropItem] {
		if let f = Model.cachedFilteredDrops {
			return f
		} else {
			return drops
		}
	}
	
	func removeItemFromList(uuid: UUID) {
		if let x = drops.index(where: { $0.uuid == uuid }) {
			drops.remove(at: x)
		}
		if Model.cachedFilteredDrops != nil, let x = Model.cachedFilteredDrops!.index(where: { $0.uuid == uuid }) {
			Model.cachedFilteredDrops!.remove(at: x)
		}
	}
	
	private static let filePresenter = ModelFilePresenter()
	
	@objc private func foregrounded() {
		reloadDataIfNeeded()
		NSFileCoordinator.addFilePresenter(Model.filePresenter)
	}
	
	@objc private func backgrounded() {
		NSFileCoordinator.removeFilePresenter(Model.filePresenter)
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

	func importData(from url: URL, completion: @escaping (Bool)->Void) {
		NSLog("URL for importing: \(url.path)")

		let fm = FileManager.default
		defer {
			try? fm.removeItem(at: url)
		}

		guard
			let data = try? Data(contentsOf: url.appendingPathComponent("items.json"), options: [.alwaysMapped]),
			let itemsInPackage = try? JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
		else {
			completion(false)
			return
		}

		let itemsToImport = itemsInPackage.filter { !drops.contains($0) }

		if itemsToImport.count == 0 {
			completion(true)
			return
		}

		drops.insert(contentsOf: itemsToImport, at: 0)

		for item in itemsToImport {

			let uuid = item.uuid.uuidString

			let localPath = Model.appStorageUrl.appendingPathComponent(uuid)
			if fm.fileExists(atPath: localPath.path) {
				try! fm.removeItem(at: localPath)
			}

			let remotePath = url.appendingPathComponent(uuid)
			try! fm.moveItem(at: remotePath, to: localPath)
		}

		reIndex(items: itemsToImport) {
			DispatchQueue.main.async {
				self.save()
				NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
				completion(true)
			}
		}
	}
}
