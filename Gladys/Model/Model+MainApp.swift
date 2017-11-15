
import CoreSpotlight
import WatchConnectivity
import CloudKit
import UIKit

private class WatchDelegate: NSObject, WCSessionDelegate {

	override init() {
		super.init()
		let session = WCSession.default
		session.delegate = self
		session.activate()
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		updateContext()
	}

	func sessionDidBecomeInactive(_ session: WCSession) {}

	func sessionDidDeactivate(_ session: WCSession) {}

	func sessionReachabilityDidChange(_ session: WCSession) {
		if session.isReachable && session.applicationContext.count == 0 && Model.drops.count > 0 {
			updateContext()
		}
	}

	func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
		DispatchQueue.main.async {

			if let uuidForView = message["view"] as? String {
				ViewController.shared.highlightItem(with: uuidForView, andOpen: true)
				DispatchQueue.global().async {
					replyHandler([:])
				}
			}

			if let uuidForCopy = message["copy"] as? String {
				if let i = Model.item(uuid: uuidForCopy) {
					i.copyToPasteboard()
				}
				DispatchQueue.global().async {
					replyHandler([:])
				}
			}

			if let uuidForImage = message["image"] as? String {
				if let i = Model.item(uuid: uuidForImage) {
					let mode = i.displayMode
					let icon = i.displayIcon
					DispatchQueue.global().async {
						let limit: CGFloat = (mode == .center || mode == .circle) ? 0.7 : 1.0
						let size = (mode == .center || mode == .circle) ? CGSize(width: 22, height: 22) : CGSize(width: 40, height: 40)
						let scaledImage = icon.limited(to: size, limitTo: limit)
						let data = UIImagePNGRepresentation(scaledImage)!
						replyHandler(["imagePng": data])
					}
				} else {
					DispatchQueue.global().async {
						replyHandler([:])
					}
				}
			}
		}
	}

	func updateContext() {
		let session = WCSession.default
		guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
		do {
			try session.updateApplicationContext(["dropList": Model.drops.map { $0.watchItem }])
			log("Updated watch context")
		} catch {
			log("Error updating watch context: \(error.localizedDescription)")
		}
	}
}

//////////////////////////////////////////////////////////

extension Model {

	static var saveIsDueToSyncFetch = false

	private static var modelFilter: String?
	private static var currentFilterQuery: CSSearchQuery?
	private static var cachedFilteredDrops: [ArchivedDropItem]?

	private static var saveOverlap = 0
	private static var saveBgTask: UIBackgroundTaskIdentifier?

	private static var watchDelegate: WatchDelegate?
	
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: filePresenter)
	}

	static func prepareToSave() {
		saveOverlap += 1
		if saveBgTask == nil {
			log("Starting save queue background task")
			saveBgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.saveTask", expirationHandler: nil)
		}
		rebuildLabels()
	}

	static func startupComplete() {

		// cleanup, in case of previous crashes, cancelled transfers, etc

		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(at: appStorageUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else { return }
		let uuids = items.flatMap { UUID(uuidString: $0.lastPathComponent) }
		let nonExistingUUIDs = uuids.filter { uuid -> Bool in
			return !drops.contains { $0.uuid == uuid }
		}
		for uuid in nonExistingUUIDs {
			let url = appStorageUrl.appendingPathComponent(uuid.uuidString)
			try? fm.removeItem(at: url)
		}

		rebuildLabels()

		if WCSession.isSupported() {
			watchDelegate = WatchDelegate()
		}
	}

	static func saveComplete() {
		NotificationCenter.default.post(name: .SaveComplete, object: nil)
		if saveIsDueToSyncFetch {
			saveIsDueToSyncFetch = false
			log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
		} else {
			CloudManager.sync { error in
				if let error = error {
					log("Error in push after save: \(error.finalDescription)")
				}
			}
		}

		saveOverlap -= 1
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
			if saveOverlap == 0, let b = saveBgTask {
				watchDelegate?.updateContext()
				log("Ending save queue background task")
				UIApplication.shared.endBackgroundTask(b)
				saveBgTask = nil
			}
		}
	}
	
	static func beginMonitoringChanges() {
		let n = NotificationCenter.default
		n.addObserver(forName: .UIApplicationWillEnterForeground, object: nil, queue: OperationQueue.main) { _ in
			foregrounded()
		}
		n.addObserver(forName: .UIApplicationDidEnterBackground, object: nil, queue: OperationQueue.main) { _ in
			backgrounded()
		}
		foregrounded()
	}
	
	static var sizeInBytes: Int64 {
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

	static var isFilteringLabels: Bool {
		return labelToggles.contains { $0.enabled }
	}

	static func disableAllLabels() {
		labelToggles = labelToggles.map {
			if $0.enabled {
				var l = $0
				l.enabled = false
				return l
			} else {
				return $0
			}
		}
	}

	static func rebuildLabels() {
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

		let previous = labelToggles
		labelToggles.removeAll()
		for (label, count) in counts {
			let previousEnabled = (previous.first { $0.enabled == true && $0.name == label } != nil)
			let toggle = LabelToggle(name: label, count: count, enabled: previousEnabled, emptyChecker: false)
			labelToggles.append(toggle)
		}
		if labelToggles.count > 0 {
			labelToggles.sort { $0.name < $1.name }
			
			let name = "Items with no labels"
			let previousEnabled = (previous.first { $0.enabled == true && $0.name == name } != nil)
			labelToggles.append(LabelToggle(name: name, count: noLabelCount, enabled: previousEnabled, emptyChecker: true))
		}
	}

	static var enabledLabelsForItems: [String] {
		return labelToggles.flatMap { $0.enabled && !$0.emptyChecker ? $0.name : nil }
	}

	static var enabledLabelsForTitles: [String] {
		return labelToggles.flatMap { $0.enabled ? $0.name : nil }
	}

	static func updateLabel(_ label: LabelToggle) {
		if let i = labelToggles.index(where: { $0.name == label.name }) {
			labelToggles[i] = label
		}
	}

	static var isFilteringText: Bool {
		return currentFilterQuery != nil
	}

	static var filter: String? {
		get {
			return modelFilter
		}
		set {
			guard modelFilter != newValue else {
				return
			}
			forceUpdateFilter(with: newValue, signalUpdate: true)
		}
	}

	static func forceUpdateFilter(signalUpdate: Bool) {
		forceUpdateFilter(with: modelFilter, signalUpdate: signalUpdate)
	}

	private static func forceUpdateFilter(with newValue: String?, signalUpdate: Bool) {
		currentFilterQuery = nil
		modelFilter = newValue

		let previouslyVisibleUuids = visibleUuids
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
					log("Search error: \(error.finalDescription)")
				}
				group.leave()
			}
			currentFilterQuery = q

			q.start()
			group.wait()

			cachedFilteredDrops = postLabelDrops.filter { replacementResults.contains($0.uuid.uuidString) }
		} else {
			cachedFilteredDrops = postLabelDrops
		}

		if signalUpdate && previouslyVisibleUuids != visibleUuids {

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

	private static var visibleUuids: [UUID] {
		return (cachedFilteredDrops ?? drops).map { $0.uuid }
	}

	static func removeLabel(_ label : String) {
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
			for i in itemsNeedingReIndex {
				i.needsCloudPush = true
			}
			Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: itemsNeedingReIndex.map { $0.uuid.uuidString }) {
				DispatchQueue.main.async {
					self.save()
				}
			}
		}
	}

	static func nearestUnfilteredIndexForFilteredIndex(_ index: Int) -> Int {
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

	private static var postLabelDrops: [ArchivedDropItem] {
		let enabledToggles = labelToggles.filter { $0.enabled }
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

	static func resetEverything() {
		for item in drops {
			item.delete()
		}
		drops.removeAll()
		modelFilter = nil
		cachedFilteredDrops = nil
		save()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	static var filteredDrops: [ArchivedDropItem] {
		if let f = cachedFilteredDrops {
			return f
		} else {
			return drops
		}
	}
	
	static func removeItemFromList(uuid: UUID) {
		if let x = drops.index(where: { $0.uuid == uuid }) {
			drops.remove(at: x)
		}
		if cachedFilteredDrops != nil, let x = cachedFilteredDrops!.index(where: { $0.uuid == uuid }) {
			cachedFilteredDrops!.remove(at: x)
		}
	}
	
	private static let filePresenter = ModelFilePresenter()
	
	private static func foregrounded() {
		NSFileCoordinator.addFilePresenter(filePresenter)
		reloadDataIfNeeded()
	}

	private static func backgrounded() {
		NSFileCoordinator.removeFilePresenter(filePresenter)
	}
	
	private class ModelFilePresenter: NSObject, NSFilePresenter {
				
		var presentedItemURL: URL? {
			return fileUrl
		}
		
		var presentedItemOperationQueue: OperationQueue {
			return OperationQueue.main
		}
		
		func presentedItemDidChange() {
			reloadDataIfNeeded()
		}
	}

	static func reloadCompleted() {
		rebuildLabels()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	static func importData(from url: URL, completion: @escaping (Bool)->Void) {
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
				save()
				NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
			}
			completion(true)
		}
	}
}
