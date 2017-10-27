
import CoreSpotlight
import CloudKit
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
		rebuildLabels()
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

		rebuildLabels()
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
		CloudManager.sync { error in
			if let error = error {
				log("Error in push after safe: \(error.localizedDescription)")
			}
		}
	}
	
	func beginMonitoringChanges() {
		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(foregrounded), name: .UIApplicationWillEnterForeground, object: nil)
		n.addObserver(self, selector: #selector(backgrounded), name: .UIApplicationDidEnterBackground, object: nil)
		foregrounded()
	}
	
	var sizeInBytes: Int64 {
		return drops.reduce(0, { $0 + $1.sizeInBytes })
	}
	
	////////////////////////// Filtering

	struct LabelToggle {
		let name: String
		let count: Int
		var enabled: Bool
		let emptyChecker: Bool
	}

	static var labelToggles = [LabelToggle]()

	var isFilteringLabels: Bool {
		return Model.labelToggles.contains { $0.enabled }
	}

	func disableAllLabels() {
		Model.labelToggles = Model.labelToggles.map {
			if $0.enabled {
				var l = $0
				l.enabled = false
				return l
			} else {
				return $0
			}
		}
	}

	private func rebuildLabels() {
		var counts = [String:Int]()
		var noLabelCount = 0
		for item in drops {
			item.labels.forEach {
				if let c = counts[$0] {
					counts[$0] = c+1
				} else {
					counts[$0] = 1
				}
			}
			if item.labels.count == 0 {
				noLabelCount += 1
			}
		}

		let previous = Model.labelToggles
		Model.labelToggles.removeAll()
		for (label, count) in counts {
			let previousEnabled = (previous.first { $0.enabled == true && $0.name == label } != nil)
			let toggle = LabelToggle(name: label, count: count, enabled: previousEnabled, emptyChecker: false)
			Model.labelToggles.append(toggle)
		}
		if Model.labelToggles.count > 0 {
			Model.labelToggles.sort { $0.name < $1.name }
			
			let name = "Items with no labels"
			let previousEnabled = (previous.first { $0.enabled == true && $0.name == name } != nil)
			Model.labelToggles.append(LabelToggle(name: name, count: noLabelCount, enabled: previousEnabled, emptyChecker: true))
		}
	}

	var enabledLabelsForItems: [String] {
		return Model.labelToggles.flatMap { $0.enabled && !$0.emptyChecker ? $0.name : nil }
	}

	var enabledLabelsForTitles: [String] {
		return Model.labelToggles.flatMap { $0.enabled ? $0.name : nil }
	}

	func updateLabel(_ label: LabelToggle) {
		if let i = Model.labelToggles.index(where: { $0.name == label.name }) {
			Model.labelToggles[i] = label
		}
	}

	var isFilteringText: Bool {
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
			forceUpdateFilter(with: newValue, signalUpdate: true)
		}
	}

	func forceUpdateFilter(signalUpdate: Bool) {
		forceUpdateFilter(with: Model.modelFilter, signalUpdate: signalUpdate)
	}

	private func forceUpdateFilter(with newValue: String?, signalUpdate: Bool) {
		Model.currentFilterQuery = nil
		Model.modelFilter = newValue

		let olduuids = filteredUuids
		var filtering = false

		if let f = filter, !f.isEmpty {

			filtering = true

			var replacementResults = [String]()

			let group = DispatchGroup()
			group.enter()

			let criterion = "\"*\(f)*\"cd"
			let q = CSSearchQuery(queryString: "title == \(criterion) || contentDescription == \(criterion) || keywords == \(criterion)", attributes: nil)
			q.foundItemsHandler = { items in
				let uuids = items.map { $0.uniqueIdentifier }
				replacementResults.append(contentsOf: uuids)
			}
			q.completionHandler = { error in
				if let error = error {
					log("Search error: \(error.localizedDescription)")
				}
				group.leave()
			}
			Model.currentFilterQuery = q

			q.start()
			group.wait()

			Model.cachedFilteredDrops = postLabelDrops.filter { replacementResults.contains($0.uuid.uuidString) }
		} else {
			Model.cachedFilteredDrops = postLabelDrops
		}

		if signalUpdate && olduuids != filteredUuids {

			NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: nil)

			if filtering && UIAccessibilityIsVoiceOverRunning() {
				let resultString: String
				let c = filteredDrops.count
				if c == 0 {
					resultString = "No results"
				} else if c == 1 {
					resultString = "One result"
				} else  {
					resultString = "\(filteredDrops.count) results"
				}
				UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, resultString)
			}
		}
	}

	private var filteredUuids: [String] {
		return Model.cachedFilteredDrops?.map({ $0.uuid.uuidString }) ?? []
	}

	func removeLabel(_ label : String) {
		var itemsNeedingReIndex = [ArchivedDropItem]()
		for i in drops {
			if i.labels.contains(label) {
				i.labels = i.labels.filter { $0 != label }
				itemsNeedingReIndex.append(i)
			}
		}
		rebuildLabels()
		if itemsNeedingReIndex.count > 0 {
			NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
			reIndex(items: itemsNeedingReIndex) {
				DispatchQueue.main.async {
					self.save()
				}
			}
		}
	}

	func nearestUnfilteredIndexForFilteredIndex(_ index: Int) -> Int {
		guard isFilteringText || isFilteringLabels else {
			return index
		}
		if drops.count == 0 {
			return 0
		}
		let closestItem: ArchivedDropItem
		if index >= filteredDrops.count {
			closestItem = filteredDrops.last!
			if let i = drops.index(of: closestItem) {
				return i+1
			}
			return 0
		} else {
			closestItem = filteredDrops[index]
			return drops.index(of: closestItem) ?? 0
		}
	}

	private var postLabelDrops: [ArchivedDropItem] {
		let enabledToggles = Model.labelToggles.filter { $0.enabled }
		if enabledToggles.count == 0 { return drops }

		return drops.filter { item in
			for toggle in enabledToggles {
				if toggle.emptyChecker {
					if item.labels.count == 0 {
						return true
					}
				} else if item.labels.contains(toggle.name) {
					return true
				}
			}
			return false
		}
	}

	func resetEverything() {
		for item in drops {
			item.delete()
		}
		drops.removeAll()
		Model.modelFilter = nil
		Model.cachedFilteredDrops = nil
		save()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
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
				
		var presentedItemURL: URL? {
			return Model.fileUrl
		}
		
		var presentedItemOperationQueue: OperationQueue {
			return OperationQueue.main
		}
		
		func presentedItemDidChange() {
			model.reloadDataIfNeeded()
		}
	}

	func reloadCompleted() {
		rebuildLabels()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
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

		var itemsImported = 0

		for item in itemsInPackage.reversed() {

			if let i = drops.index(of: item) {
				if drops[i].updatedAt >= item.updatedAt {
					continue
				}
				drops[i] = item
			} else {
				drops.insert(item, at: 0)
			}

			itemsImported += 1
			item.needsReIngest = true
			item.markUpdated()

			let localPath = item.folderUrl
			if fm.fileExists(atPath: localPath.path) {
				try! fm.removeItem(at: localPath)
			}

			let remotePath = url.appendingPathComponent(item.uuid.uuidString)
			try! fm.moveItem(at: remotePath, to: localPath)

			item.cloudKitRecord = nil
			for typeItem in item.typeItems {
				typeItem.cloudKitRecord = nil
			}
		}

		DispatchQueue.main.async {
			if itemsImported > 0 {
				self.save()
				NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
			}
			completion(true)
		}
	}
}
