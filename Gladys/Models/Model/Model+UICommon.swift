//
//  Model+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CoreSpotlight
import CloudKit
#if os(iOS)
import CoreAudioKit
#else
import Cocoa
#endif

extension Model {
	static var saveIsDueToSyncFetch = false

	private static var modelFilter: String?
	private static var currentFilterQuery: CSSearchQuery?
	private static var cachedFilteredDrops: [ArchivedDropItem]?
	private static let saveQueue = DispatchQueue(label: "build.bru.Gladys.saveQueue", qos: .background)
	private static var needsAnotherSave = false
	private static var isSaving = false
	private static var nextSaveCallbacks: [()->Void]?

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

	static var labelToggles = [LabelToggle]()

	struct LabelToggle {
		let name: String
		let count: Int
		var enabled: Bool
		let emptyChecker: Bool

		enum State {
			case none, some, all
			var accessibilityValue: String? {
				switch self {
				case .none: return nil
				case .some: return "Applied to some selected items"
				case .all: return "Applied to all selected items"
				}
			}
		}

		func toggleState(across uuids: [UUID]?) -> State {
			let n = uuids?.reduce(0) { total, uuid -> Int in
				if let item = Model.item(uuid: uuid), item.labels.contains(name) {
					return total + 1
				}
				return total
				} ?? 0
			if n == (uuids?.count ?? -1) {
				return .all
			}
			return n > 0 ? .some : .none
		}
	}

	enum SortOption {
		case dateAdded, dateModified, title, note, size, label
		var ascendingTitle: String {
			switch self {
			case .dateAdded: return "Oldest First"
			case .dateModified: return "Oldest Modified First"
			case .title: return "Title (A-Z)"
			case .note: return "Note (A-Z)"
			case .label: return "First Label (A-Z)"
			case .size: return "Smallest First"
			}
		}
		var descendingTitle: String {
			switch self {
			case .dateAdded: return "Newest First"
			case .dateModified: return "Newest Modified First"
			case .title: return "Title (Z-A)"
			case .note: return "Note (Z-A)"
			case .label: return "First Label (Z-A)"
			case .size: return "Largest First"
			}
		}
		private func sortElements(itemsToSort: [ArchivedDropItem]) -> ([ArchivedDropItem], [Int]) {
			var itemIndexes = [Int]()
			let toCheck = itemsToSort.isEmpty ? Model.drops : itemsToSort
			let actualItemsToSort = toCheck.compactMap { item -> ArchivedDropItem? in
				if let index = Model.drops.firstIndex(of: item) {
					itemIndexes.append(index)
					return item
				}
				return nil
			}
			assert(actualItemsToSort.count == itemIndexes.count)
			return (actualItemsToSort, itemIndexes.sorted())
		}
		func handlerForSort(itemsToSort: [ArchivedDropItem], ascending: Bool) -> ()->Void {
			var (actualItemsToSort, itemIndexes) = sortElements(itemsToSort: itemsToSort)
			let sortType = self
			return {
				switch sortType {
				case .dateAdded:
					if ascending {
						actualItemsToSort.sort { $0.createdAt < $1.createdAt }
					} else {
						actualItemsToSort.sort { $0.createdAt > $1.createdAt }
					}
				case .dateModified:
					if ascending {
						actualItemsToSort.sort { $0.updatedAt < $1.updatedAt }
					} else {
						actualItemsToSort.sort { $0.updatedAt > $1.updatedAt }
					}
				case .title:
					if ascending {
						actualItemsToSort.sort { $0.displayTitleOrUuid < $1.displayTitleOrUuid }
					} else {
						actualItemsToSort.sort { $0.displayTitleOrUuid > $1.displayTitleOrUuid }
					}
				case .note:
					if ascending {
						actualItemsToSort.sort { $0.note < $1.note }
					} else {
						actualItemsToSort.sort { $0.note > $1.note }
					}
				case .label:
					if ascending {
						actualItemsToSort.sort { $0.labels.first ?? "" < $1.labels.first ?? "" }
					} else {
						actualItemsToSort.sort { $0.labels.first ?? "" > $1.labels.first ?? "" }
					}
				case .size:
					if ascending {
						actualItemsToSort.sort { $0.sizeInBytes < $1.sizeInBytes }
					} else {
						actualItemsToSort.sort { $0.sizeInBytes > $1.sizeInBytes }
					}
				}
				for pos in 0 ..< itemIndexes.count {
					let itemIndex = itemIndexes[pos]
					let item = actualItemsToSort[pos]
					Model.drops[itemIndex] = item
				}
				Model.forceUpdateFilter(signalUpdate: false)
				Model.save()
			}
		}
		static var options: [SortOption] { return [SortOption.dateAdded, SortOption.dateModified, SortOption.title, SortOption.note, SortOption.label, SortOption.size] }
	}

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

	static func reloadCompleted() {
		rebuildLabels()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
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
		if let i = labelToggles.firstIndex(where: { $0.name == label.name }) {
			labelToggles[i] = label
		}
	}

	static var isFilteringText: Bool {
		return currentFilterQuery != nil
	}

	static var isFiltering: Bool {
		return isFilteringText || isFilteringLabels
	}

	static var filteredDrops: [ArchivedDropItem] {
		return cachedFilteredDrops ?? drops
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
				terms.append("title == \(criterion) || textContent == \(criterion) || contentDescription == \(criterion) || keywords == \(criterion)")
			}
		} catch {
			log("Warning regex error: \(error.localizedDescription)")
		}
		return terms
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
			if let i = drops.firstIndex(of: closestItem) {
				return i+1
			}
			return 0
		} else if index > 0 {
			closestItem = filteredDrops[index-1]
			return (drops.firstIndex(of: closestItem) ?? 0) + 1
		} else {
			closestItem = filteredDrops[0]
			return drops.firstIndex(of: closestItem) ?? 0
		}
	}

	private static var postLabelDrops: [ArchivedDropItem] {
		let enabledToggles = labelToggles.filter { $0.enabled }
		if enabledToggles.count == 0 { return drops }

		if PersistedOptions.exclusiveMultipleLabels {
			let expectedCount = enabledToggles.count
			return drops.filter { item in
				var matchCount = 0
				for toggle in enabledToggles {
					if toggle.emptyChecker {
						if item.labels.count == 0 {
							matchCount += 1
						}
					} else if item.labels.contains(toggle.name) {
						matchCount += 1
					}
				}
				return matchCount == expectedCount
			}

		} else {
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
	}

	static func resetEverything() {
		drops.filter { !$0.isImportedShare }.forEach { $0.delete() }
		drops.removeAll { !$0.isImportedShare }
		modelFilter = nil
		cachedFilteredDrops = nil
		clearCaches()
		save()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	static func removeImportedShares() {
		drops.removeAll { $0.isImportedShare }
		save()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
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

	@discardableResult
	static func forceUpdateFilter(with newValue: String? = modelFilter, signalUpdate: Bool) -> Bool {
		currentFilterQuery = nil
		modelFilter = newValue

		let previouslyVisibleUuids = filteredDrops.map { $0.uuid }
		var filtering = false

		if let terms = terms(for: filter), !terms.isEmpty {

			filtering = true

			var replacementResults = [String]()

			let group = DispatchGroup()
			group.enter()

			let queryString: String
			if 	terms.count > 1 {
				if PersistedOptions.inclusiveSearchTerms {
					queryString = "(" + terms.joined(separator: ") || (") + ")"
				} else {
					queryString = "(" + terms.joined(separator: ") && (") + ")"
				}
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

		let changesToVisibleItems = previouslyVisibleUuids != filteredDrops.map { $0.uuid }
		if signalUpdate && changesToVisibleItems {

			NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: nil)

			#if os(iOS)
			if filtering && UIAccessibility.isVoiceOverRunning {
				let resultString: String
				let c = filteredDrops.count
				if c == 0 {
					resultString = "No results"
				} else if c == 1 {
					resultString = "One result"
				} else  {
					resultString = "\(filteredDrops.count) results"
				}
				UIAccessibility.post(notification: .announcement, argument: resultString)
			}
			#endif
		}

		return changesToVisibleItems
	}

	static func removeItemsFromZone(_ zoneID: CKRecordZone.ID) {
		let itemsRelatedToZone = drops.filter { $0.parentZone == zoneID }
		for item in itemsRelatedToZone {
			item.removeFromCloudkit()
		}
		_ = delete(items: itemsRelatedToZone)
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	static var sharingMyItems: Bool {
		return drops.contains { $0.shareMode == .sharing }
	}

	static var containsImportedShares: Bool {
		return drops.contains { $0.isImportedShare }
	}

	static var itemsIAmSharing: [ArchivedDropItem] {
		return drops.filter { $0.shareMode == .sharing }
	}

	static func duplicate(item: ArchivedDropItem) {
		if let previousIndex = drops.firstIndex(of: item) {
			let newItem = ArchivedDropItem(cloning: item)
			drops.insert(newItem, at: previousIndex+1)
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
		}
	}

	static func delete(items: [ArchivedDropItem]) -> [IndexPath] {
		var ipsToRemove = [IndexPath]()
		var uuidsToRemove = [UUID]()

		for item in items {

			if item.shouldDisplayLoading {
				item.cancelIngest()
			}

			let uuid = item.uuid
			uuidsToRemove.append(uuid)

			if let i = filteredDrops.firstIndex(where: { $0.uuid == uuid }) {
				ipsToRemove.append(IndexPath(item: i, section: 0))
			}

			item.delete()
		}

		for uuid in uuidsToRemove {
			if let x = drops.firstIndex(where: { $0.uuid == uuid }) {
				drops.remove(at: x)
			}
			if let x = cachedFilteredDrops?.firstIndex(where: { $0.uuid == uuid }) {
				cachedFilteredDrops!.remove(at: x)
			}
		}

		return ipsToRemove
	}

	static var doneIngesting: Bool {
		return !drops.contains { ($0.needsReIngest && !$0.isDeleting) || ($0.loadingProgress != nil && $0.loadingError == nil) }
	}

	static var itemsToReIngest: [ArchivedDropItem] {
		return drops.filter { $0.needsReIngest && $0.loadingProgress == nil && !$0.isDeleting }
	}

	static func lockUnlockedItems() {
		for item in drops where item.isTemporarilyUnlocked {
			item.needsUnlock = true
			item.postModified()
		}
	}

	///////////////////////// Migrating

	static func checkForUpgrade() {
		let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		#if DEBUG
		migration(to: currentBuild)
		#else
		if PersistedOptions.lastRanVersion != currentBuild {
			migration(to: currentBuild)
		}
		#endif
	}

	private static func migration(to currentBuild: String) {
		if CloudManager.syncSwitchedOn && CloudManager.lastiCloudAccount == nil {
			CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
		}
		if Model.legacyMode {
			log("Migrating legacy data store")
			for i in Model.drops {
				i.needsSaving = true
			}
			Model.save()
			Model.legacyMode = false
			log("Migration done")
		}
		Model.searchableIndex(CSSearchableIndex.default(), reindexAllSearchableItemsWithAcknowledgementHandler: {
			PersistedOptions.lastRanVersion = currentBuild
		})
	}

	//////////////////////// Saving

	static func queueNextSaveCallback(_ callback: @escaping ()->Void) {
		if nextSaveCallbacks == nil {
			nextSaveCallbacks = [()->Void]()
		}
		nextSaveCallbacks!.append(callback)
	}

	static func save() {
		if isSaving {
			needsAnotherSave = true
		} else {
			prepareToSave()
			performSave()
		}
	}
    
    static func performFirstMirror(completion: @escaping ()->Void) {
        let itemsToSave = drops.filter { $0.goodToSave }
        saveQueue.async {
            do {
                try FileAreaManager.mirrorToFiles(from: itemsToSave)
            } catch {
                log("Error while performing first mirror: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    static func disableMirror(completion: @escaping ()->Void) {
        saveQueue.async {
            do {
                try FileAreaManager.removeMirrorIfNeeded()
            } catch {
                log("Error while disabling mirror: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

	private static func performSave() {

		let itemsToSave = drops.filter { $0.goodToSave }
        
        let itemsNeedingSaving = itemsToSave.filter { $0.needsSaving}

		let uuidsToEncode = itemsNeedingSaving.map { i -> UUID in
            i.isBeingCreatedBySync = false
            i.needsSaving = false
            return i.uuid
		}
        
		isSaving = true
		needsAnotherSave = false

        let shouldMirror = PersistedOptions.mirrorFilesToDocuments
        
		saveQueue.async {
			do {
				try coordinatedSave(allItems: itemsToSave, dirtyUuids: uuidsToEncode)
                if shouldMirror {
                    try FileAreaManager.mirrorToFiles(from: itemsNeedingSaving)
                }
			} catch {
				log("Saving Error: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				if needsAnotherSave {
					performSave()
				} else {
					isSaving = false
					if let n = nextSaveCallbacks {
						for callback in n {
							callback()
						}
						nextSaveCallbacks = nil
					}
					trimTemporaryDirectory()
					saveComplete()
				}
			}
		}
	}

	static func saveIndexOnly() {
		let itemsToSave = drops.filter { $0.goodToSave }
		saveQueue.async {
			do {
				try coordinatedSave(allItems: itemsToSave, dirtyUuids: [])
				log("Saved index only")
			} catch {
				log("Warning: Error while committing index to disk: (\(error.finalDescription))")
			}
			DispatchQueue.main.async {
				saveIndexComplete()
			}
		}
	}

	static func commitItem(item: ArchivedDropItem) {
		let itemsToSave = drops.filter { $0.goodToSave }
		item.isBeingCreatedBySync = false
		item.needsSaving = false
		let uuid = item.uuid
		saveQueue.async {
			if item.isDeleting {
				log("Skipping save of item \(uuid) as it's marked for deletion")
				return
			}
			do {
				try coordinatedSave(allItems: itemsToSave, dirtyUuids: [uuid])
				log("Ingest completed for item (\(uuid)) and committed to disk")
			} catch {
				log("Warning: Error while committing item to disk: (\(error.finalDescription))")
			}
		}
	}

	private static func coordinatedSave(allItems: [ArchivedDropItem], dirtyUuids: [UUID]) throws {
		if brokenMode {
			log("Ignoring save, model is broken, app needs restart.")
			return
		}
		var closureError: NSError?
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			let start = Date()
			log("Saving: \(allItems.count) uuids, \(dirtyUuids.count) updated data files")
			do {
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
                        try e.encode(item).write(to: url.appendingPathComponent(u.uuidString), options: .atomic)
					}
				}
				try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

				if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String] {
					if (filesInDir.count - 1) > allItems.count { // old file exists, let's find it
						let uuidStrings = allItems.map { $0.uuid.uuidString }
						for file in filesInDir {
							if !uuidStrings.contains(file) && file != "uuids" { // old file
								log("Removing save file for non-existent item: \(file)")
								try? fm.removeItem(atPath: url.appendingPathComponent(file).path)
							}
						}
					}
				}

				if fm.fileExists(atPath: legacyFileUrl.path) {
					try? fm.removeItem(at: legacyFileUrl)
				}

				if let dataModified = modificationDate(for: url) {
					dataFileLastModified = dataModified
				}

				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				closureError = error as NSError
			}
		}
		if let e = coordinationError ?? closureError {
			throw e
		}
	}
}
