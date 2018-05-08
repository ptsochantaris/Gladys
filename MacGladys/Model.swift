
import Foundation
import CoreSpotlight

final class Model {

	static func reset() {
		drops.removeAll(keepingCapacity: false)
		dataFileLastModified = .distantPast
	}

	static func reloadDataIfNeeded() {

		var didLoad = false
		let url = itemsDirectoryUrl

		if FileManager.default.fileExists(atPath: url.path) {
			do {

				var shouldLoad = true
				if let dataModified = modificationDate(for: url) {
					if dataModified == dataFileLastModified {
						shouldLoad = false
					} else {
						dataFileLastModified = dataModified
					}
				}
				if shouldLoad {
					log("Needed to reload data, new file date: \(dataFileLastModified)")
					didLoad = true

					let start = Date()

					let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
					let itemCount = d.count / 16
					var newDrops = [ArchivedDropItem]()
					newDrops.reserveCapacity(itemCount)
					var c = 0
					let decoder = JSONDecoder()
					while c < d.count {
						let d0 = d[c]; let d1 = d[c+1]; let d2 = d[c+2]; let d3 = d[c+3]
						let d4 = d[c+4]; let d5 = d[c+5]; let d6 = d[c+6]; let d7 = d[c+7]
						let d8 = d[c+8]; let d9 = d[c+9]; let d10 = d[c+10]; let d11 = d[c+11]
						let d12 = d[c+12]; let d13 = d[c+13]; let d14 = d[c+14]; let d15 = d[c+15]
						let u = UUID(uuid: (d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15))
						c += 16
						let dataPath = url.appendingPathComponent(u.uuidString)
						if let data = try? Data(contentsOf: dataPath), let item = try? decoder.decode(ArchivedDropItem.self, from: data) {
							newDrops.append(item)
						}
					}
					drops = newDrops
					log("Load time: \(-start.timeIntervalSinceNow) seconds")
				} else {
					log("No need to reload data")
				}
			} catch {
				log("Loading Error: \(error)")
			}
		} else {
			drops = []
			log("Starting fresh store")
		}

		DispatchQueue.main.async {
			if isStarted {
				if didLoad {
					reloadCompleted()
				}
			} else {
				isStarted = true
				startupComplete()
			}
		}
	}

	private static var needsAnotherSave = false
	private static var isSaving = false
	private static var nextSaveCallbacks: [()->Void]?

	static func queueNextSaveCallback(_ callback: @escaping ()->Void) {
		if nextSaveCallbacks == nil {
			nextSaveCallbacks = [()->Void]()
		}
		nextSaveCallbacks!.append(callback)
	}

	private static func performAnyNextSaveCallbacks() {
		if let n = nextSaveCallbacks {
			for callback in n {
				callback()
			}
			nextSaveCallbacks = nil
		}
	}

	static func save() {
		assert(Thread.isMainThread)

		if isSaving {
			needsAnotherSave = true
		} else {
			prepareToSave()
			performSave()
		}
	}

	static func saveIndexOnly() {

		let itemsToSave = drops.filter { $0.goodToSave }

		saveQueue.async {
			let url = itemsDirectoryUrl
			do {
				log("Storing updated item index")

				var uuidData = Data()
				uuidData.reserveCapacity(itemsToSave.count * 16)
				for item in itemsToSave {
					let u = item.uuid
					let t = u.uuid
					uuidData.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
				}

				let fm = FileManager.default
				if !fm.fileExists(atPath: url.path) {
					try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
				}
				try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

				if let dataModified = modificationDate(for: url) {
					dataFileLastModified = dataModified
				}
			} catch {
				log("Saving index coordination error: \(error.finalDescription)")
			}
		}
	}

	private static let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	private static func performSave() {

		let start = Date()

		let itemsToSave = drops.filter { $0.goodToSave }
		let uuidsToEncode = itemsToSave.compactMap { i -> UUID? in
			if i.needsSaving {
				i.needsSaving = false
				return i.uuid
			}
			return nil
		}

		isSaving = true
		needsAnotherSave = false

		saveQueue.async {

			do {
				log("\(itemsToSave.count) items to save, \(uuidsToEncode.count) items to encode")
				try self.coordinatedSave(allItems: itemsToSave, dirtyUuids: uuidsToEncode)
				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				log("Saving Error: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				if needsAnotherSave {
					performSave()
				} else {
					isSaving = false
					performAnyNextSaveCallbacks()
					saveComplete()
				}
			}
		}
	}

	private static func coordinatedSave(allItems: [ArchivedDropItem], dirtyUuids: [UUID]) throws {
		let url = itemsDirectoryUrl
		let fm = FileManager.default
		if !fm.fileExists(atPath: url.path) {
			try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}

		let e = dirtyUuids.count > 0 ? JSONEncoder() : nil

		var uuidData = Data()
		uuidData.reserveCapacity(allItems.count * 16)
		for item in allItems {
			let u = item.uuid
			let t = u.uuid
			uuidData.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
			if let e = e, dirtyUuids.contains(u) {
				try autoreleasepool {
					try e.encode(item).write(to: url.appendingPathComponent(u.uuidString), options: .atomic)
				}
			}
		}
		try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

		if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String] {
			if (filesInDir.count - 1) > allItems.count { // old file exists, let's find it
				let uuidStrings = allItems.map { $0.uuid.uuidString }
				for file in filesInDir {
					if !uuidStrings.contains(file) && file != "uuids" { // old file
						log("Removing file for non-existent item: \(file)")
						try? fm.removeItem(atPath: url.appendingPathComponent(file).path)
					}
				}
			}
		}

		if let dataModified = modificationDate(for: url) {
			dataFileLastModified = dataModified
		}
	}

	static var saveIsDueToSyncFetch = false

	private static var modelFilter: String?
	private static var currentFilterQuery: CSSearchQuery?
	private static var cachedFilteredDrops: [ArchivedDropItem]?

	static func prepareToSave() {
		rebuildLabels()
	}

	static func startupComplete() {

		// cleanup, in case of previous crashes, cancelled transfers, etc

		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(at: appStorageUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else { return }
		let uuids = items.compactMap { UUID(uuidString: $0.lastPathComponent) }
		let nonExistingUUIDs = uuids.filter { uuid -> Bool in
			return !drops.contains { $0.uuid == uuid }
		}
		for uuid in nonExistingUUIDs {
			let url = appStorageUrl.appendingPathComponent(uuid.uuidString)
			try? fm.removeItem(at: url)
		}

		rebuildLabels()
	}

	static func saveComplete() {
		NotificationCenter.default.post(name: .SaveComplete, object: nil)
		if saveIsDueToSyncFetch {
			saveIsDueToSyncFetch = false
			log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
		} else {
			log("Will sync up after a local save")
			CloudManager.sync { error in
				if let error = error {
					log("Error in push after save: \(error.finalDescription)")
				}
			}
		}
	}

	static var sizeInBytes: Int64 {
		return drops.reduce(0, { $0 + $1.sizeInBytes })
	}

	static var filteredSizeInBytes: Int64 {
		return filteredDrops.reduce(0, { $0 + $1.sizeInBytes })
	}

	static func sizeForItems(uuids: [UUID]) -> Int64 {
		return drops.reduce(0, { $0 + (uuids.contains($1.uuid) ? $1.sizeInBytes : 0) })
	}

	static var sizeOfVisibleItemsInBytes: Int64 {
		return filteredDrops.reduce(0, { $0 + $1.sizeInBytes })
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
		return labelToggles.compactMap { $0.enabled && !$0.emptyChecker ? $0.name : nil }
	}

	static var enabledLabelsForTitles: [String] {
		return labelToggles.compactMap { $0.enabled ? $0.name : nil }
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
			if modelFilter == newValue { return }
			forceUpdateFilter(with: newValue, signalUpdate: true)
		}
	}

	static private func terms(for f: String?) -> [String]? {
		guard let f = f?.replacingOccurrences(of: "”", with: "\"").replacingOccurrences(of: "“", with: "\"") else { return nil }

		var terms = [String]()
		do {
			let regex = try NSRegularExpression(pattern: "(\\b\\S+?\\b|\\B\\\".+?\\\"\\B)")
			regex.matches(in: f, range: NSRange(f.startIndex..., in: f)).forEach {
				let s = f[Range($0.range, in: f)!]
				let term = s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
				let criterion = "\"*\(term)*\"cd"
				terms.append("title == \(criterion) || contentDescription == \(criterion) || keywords == \(criterion)")
			}
		} catch {
			log("Warning regex error: \(error.localizedDescription)")
		}
		return terms
	}

	@discardableResult
	static func forceUpdateFilter(with newValue: String? = modelFilter, signalUpdate: Bool) -> Bool {
		currentFilterQuery = nil
		modelFilter = newValue

		let previouslyVisibleUuids = visibleUuids

		if let terms = terms(for: filter), !terms.isEmpty {

			var replacementResults = [String]()

			let group = DispatchGroup()
			group.enter()

			let queryString: String
			if 	terms.count > 1 {
				queryString = "(" + terms.joined(separator: ") && (") + ")"
			} else {
				queryString = terms.first ?? ""
			}

			let q = CSSearchQuery(queryString: queryString, attributes: nil)
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

		let changesToVisibleItems = previouslyVisibleUuids != visibleUuids
		if signalUpdate && changesToVisibleItems {
			NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: nil)
		}

		return changesToVisibleItems
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

	static var isFiltering: Bool {
		return isFilteringText || isFilteringLabels
	}

	static func nearestUnfilteredIndexForFilteredIndex(_ index: Int) -> Int {
		guard isFiltering else {
			return index
		}
		if filteredDrops.count == 0 {
			return 0
		}
		let closestItem: ArchivedDropItem
		if index >= filteredDrops.count {
			closestItem = filteredDrops.last!
			if let i = drops.index(of: closestItem) {
				return i+1
			}
			return 0
		} else if index > 0 {
			closestItem = filteredDrops[index-1]
			return (drops.index(of: closestItem) ?? 0) + 1
		} else {
			closestItem = filteredDrops[0]
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
		return cachedFilteredDrops ?? drops
	}

	static func removeItemFromList(uuid: UUID) {
		if let x = drops.index(where: { $0.uuid == uuid }) {
			drops.remove(at: x)
		}
		if let x = cachedFilteredDrops?.index(where: { $0.uuid == uuid }) {
			cachedFilteredDrops!.remove(at: x)
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

	///////////////////////// Threading

	static var threadSafeDrops: [ArchivedDropItem] {
		if Thread.isMainThread {
			return drops
		} else {
			var dropsClone = [ArchivedDropItem]()
			DispatchQueue.main.sync {
				dropsClone = drops
			}
			return dropsClone
		}
	}

	static var threadSafeFilteredDrops: [ArchivedDropItem] {
		if Thread.isMainThread {
			return filteredDrops
		} else {
			var dropsClone = [ArchivedDropItem]()
			DispatchQueue.main.sync {
				dropsClone = filteredDrops
			}
			return dropsClone
		}
	}
}
