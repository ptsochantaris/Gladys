//
//  Model+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CoreSpotlight
import CloudKit
#if os(iOS)
import Foundation
import CoreAudioKit
#else
import Cocoa
#endif

final class ModelFilterContext {

    private var modelFilter: String?
    private var currentFilterQuery: CSSearchQuery?
    private var cachedFilteredDrops: ContiguousArray<ArchivedItem>?
    
    private var reloadObservation: NSObjectProtocol?
    
    init() {
        reloadObservation = NotificationCenter.default.addObserver(forName: .ModelDataUpdated, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildLabels()
        }
        rebuildLabels()
    }
    
    deinit {
        reloadObservation = nil
    }

    var filteredSizeInBytes: Int64 {
        return filteredDrops.reduce(0, { $0 + $1.sizeInBytes })
    }

    var sizeOfVisibleItemsInBytes: Int64 {
        return filteredDrops.reduce(0, { $0 + $1.sizeInBytes })
    }

    var isFilteringText: Bool {
        return currentFilterQuery != nil
    }

    var isFilteringLabels: Bool {
        return labelToggles.contains { $0.enabled }
    }

    var isFiltering: Bool {
        return isFilteringText || isFilteringLabels
    }

    var filteredDrops: ContiguousArray<ArchivedItem> {
        if cachedFilteredDrops == nil { // this array must always be separate from updates from the model
            cachedFilteredDrops = Model.drops
        }
        return cachedFilteredDrops!
    }

    var filter: String? {
        get {
            return modelFilter
        }
        set {
            let v = newValue == "" ? nil : newValue
            if modelFilter != v {
                modelFilter = v
                updateFilter(signalUpdate: true)
            }
        }
    }
    
    var threadSafeFilteredDrops: ContiguousArray<ArchivedItem> {
        if Thread.isMainThread {
            return filteredDrops
        } else {
            var dropsClone = ContiguousArray<ArchivedItem>()
            DispatchQueue.main.sync {
                dropsClone = filteredDrops
            }
            return dropsClone
        }
    }
    
    func nearestUnfilteredIndexForFilteredIndex(_ index: Int) -> Int {
        guard isFiltering else {
            return index
        }
        if filteredDrops.isEmpty {
            return 0
        }
        let closestItem: ArchivedItem
        if index >= filteredDrops.count {
            closestItem = filteredDrops.last!
            if let i = Model.drops.firstIndex(of: closestItem) {
                return i+1
            }
            return 0
        } else if index > 0 {
            closestItem = filteredDrops[index-1]
            return (Model.drops.firstIndex(of: closestItem) ?? 0) + 1
        } else {
            closestItem = filteredDrops[0]
            return Model.drops.firstIndex(of: closestItem) ?? 0
        }
    }
    
    func enableLabelsByName(_ names: Set<String>) {
        labelToggles = labelToggles.map {
            var newToggle = $0
            let effectiveName = $0.emptyChecker ? ModelFilterContext.LabelToggle.noNameTitle : $0.name
            newToggle.enabled = names.contains(effectiveName)
            return newToggle
        }
    }

    @discardableResult
    func updateFilter(signalUpdate: Bool) -> Bool {
        currentFilterQuery = nil

        let previousFilteredDrops = filteredDrops
        var filtering = false

        if let terms = Model.terms(for: modelFilter), !terms.isEmpty {

            filtering = true

            var replacementResults = [String]()

            let group = DispatchGroup()
            group.enter()

            let queryString: String
            if     terms.count > 1 {
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

        let changesToVisibleItems = previousFilteredDrops != filteredDrops
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
    
    private var postLabelDrops: ContiguousArray<ArchivedItem> {
        let enabledToggles = labelToggles.filter { $0.enabled }
        if enabledToggles.isEmpty { return Model.drops }

        if PersistedOptions.exclusiveMultipleLabels {
            let expectedCount = enabledToggles.count
            return Model.drops.filter { item in
                var matchCount = 0
                for toggle in enabledToggles {
                    if toggle.emptyChecker {
                        if item.labels.isEmpty {
                            matchCount += 1
                        }
                    } else if item.labels.contains(toggle.name) {
                        matchCount += 1
                    }
                }
                return matchCount == expectedCount
            }

        } else {
            return Model.drops.filter { item in
                for toggle in enabledToggles {
                    if toggle.emptyChecker {
                        if item.labels.isEmpty {
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
        
    var enabledLabelsForItems: [String] {
        return labelToggles.compactMap { $0.enabled && !$0.emptyChecker ? $0.name : nil }
    }

    var enabledLabelsForTitles: [String] {
        return labelToggles.compactMap { $0.enabled ? $0.name : nil }
    }
    
    var eligibleDropsForExport: ContiguousArray<ArchivedItem> {
        let items = PersistedOptions.exportOnlyVisibleItems ? threadSafeFilteredDrops : Model.threadSafeDrops
        return items.filter { $0.goodToSave }
    }
    
    var labelToggles = [LabelToggle]()

    struct LabelToggle: Hashable {
        
        static let noNameTitle = "Items with no labels"
        
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
    
    func disableAllLabels() {
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

    func rebuildLabels() {
        var counts = [String:Int]()
        var noLabelCount = 0
        for item in Model.drops {
            item.labels.forEach {
                if let c = counts[$0] {
                    counts[$0] = c+1
                } else {
                    counts[$0] = 1
                }
            }
            if item.labels.isEmpty {
                noLabelCount += 1
            }
        }

        let previous = labelToggles
        labelToggles.removeAll()
        for (label, count) in counts {
            let previousEnabled = previous.contains { $0.enabled && $0.name == label }
            let toggle = LabelToggle(name: label, count: count, enabled: previousEnabled, emptyChecker: false)
            labelToggles.append(toggle)
        }
        if !labelToggles.isEmpty {
            labelToggles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let name = ModelFilterContext.LabelToggle.noNameTitle
            let previousEnabled = previous.contains { $0.enabled && $0.name == name }
            labelToggles.append(LabelToggle(name: name, count: noLabelCount, enabled: previousEnabled, emptyChecker: true))
        }
    }

    func updateLabel(_ label: LabelToggle) {
        if let i = labelToggles.firstIndex(where: { $0.name == label.name }) {
            labelToggles[i] = label
        }
    }

    func renameLabel(_ label : String, to newLabel: String) {
        let wasEnabled = labelToggles.first { $0.name == label }?.enabled ?? false
        let affectedUuids = Model.drops.compactMap { i -> String? in
            if let index = i.labels.firstIndex(of: label) {
                if i.labels.contains(newLabel) {
                    i.labels.remove(at: index)
                } else {
                    i.labels[index] = newLabel
                }
                i.needsCloudPush = true
                return i.uuid.uuidString
            }
            return nil
        }

        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels
        
        if wasEnabled, let i = labelToggles.firstIndex(where: { $0.name == newLabel }) {
            var l = labelToggles[i]
            l.enabled = true
            labelToggles[i] = l
        }
        NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)

        if !affectedUuids.isEmpty {
            Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: affectedUuids) {
                Model.save()
            }
        }
    }
    
    func removeLabel(_ label : String) {
        let affectedUuids = Model.drops.compactMap { i -> String? in
            if i.labels.contains(label) {
                i.labels.removeAll { $0 == label }
                i.needsCloudPush = true
                return i.uuid.uuidString
            }
            return nil
        }
        
        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels
        NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)

        if !affectedUuids.isEmpty {
            Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: affectedUuids) {
                Model.save()
            }
        }
    }
}

extension Model {
	static var saveIsDueToSyncFetch = false

	static let saveQueue = DispatchQueue(label: "build.bru.Gladys.saveQueue", qos: .background)
	private static var needsAnotherSave = false
	private static var isSaving = false
	private static var nextSaveCallbacks: [()->Void]?

	static var sizeInBytes: Int64 {
		return drops.reduce(0, { $0 + $1.sizeInBytes })
	}

	static func sizeForItems(uuids: [UUID]) -> Int64 {
		return drops.reduce(0, { $0 + (uuids.contains($1.uuid) ? $1.sizeInBytes : 0) })
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
		private func sortElements(itemsToSort: ContiguousArray<ArchivedItem>) -> (ContiguousArray<ArchivedItem>, [Int]) {
			var itemIndexes = [Int]()
			let toCheck = itemsToSort.isEmpty ? Model.drops : itemsToSort
			let actualItemsToSort = toCheck.compactMap { item -> ArchivedItem? in
				if let index = Model.drops.firstIndex(of: item) {
					itemIndexes.append(index)
					return item
				}
				return nil
			}
			assert(actualItemsToSort.count == itemIndexes.count)
			return (ContiguousArray(actualItemsToSort), itemIndexes.sorted())
		}
		func handlerForSort(itemsToSort: ContiguousArray<ArchivedItem>, ascending: Bool) -> ()->Void {
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
                Model.saveIndexOnly()
			}
		}
		static var options: [SortOption] { return [SortOption.dateAdded, SortOption.dateModified, SortOption.title, SortOption.note, SortOption.label, SortOption.size] }
	}

	static fileprivate func terms(for f: String?) -> [String]? {
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

	static func resetEverything() {
        let toDelete = drops.filter { !$0.isImportedShare }
        delete(items: toDelete)
	}

	static func removeImportedShares() {
        let toDelete = drops.filter { $0.isImportedShare }
        delete(items: toDelete)
	}

	static var threadSafeDrops: ContiguousArray<ArchivedItem> {
		if Thread.isMainThread {
			return drops
		} else {
			var dropsClone = ContiguousArray<ArchivedItem>()
			DispatchQueue.main.sync {
				dropsClone = drops
			}
			return dropsClone
		}
	}

	static func removeItemsFromZone(_ zoneID: CKRecordZone.ID) {
		let itemsRelatedToZone = drops.filter { $0.parentZone == zoneID }
		for item in itemsRelatedToZone {
			item.removeFromCloudkit()
		}
		_ = delete(items: itemsRelatedToZone)
	}

	static var sharingMyItems: Bool {
		return drops.contains { $0.shareMode == .sharing }
	}

	static var containsImportedShares: Bool {
		return drops.contains { $0.isImportedShare }
	}

	static var itemsIAmSharing: ContiguousArray<ArchivedItem> {
		return drops.filter { $0.shareMode == .sharing }
	}

	static func duplicate(item: ArchivedItem) {
		if let previousIndex = drops.firstIndex(of: item) {
			let newItem = ArchivedItem(cloning: item)
			drops.insert(newItem, at: previousIndex+1)
            save()
		}
	}

    static func delete(items: [ArchivedItem]) {
        for item in items {
            item.delete()
        }
        save()
	}

	static func lockUnlockedItems() {
		for item in drops where item.isTemporarilyUnlocked {
            item.flags.insert(.needsUnlock)
			item.postModified()
		}
	}

	///////////////////////// Migrating

	static func setup() {
        reloadDataIfNeeded()
        setupIndexDelegate()
        
        // migrate if needed
		let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		if PersistedOptions.lastRanVersion != currentBuild {
            if CloudManager.syncSwitchedOn && CloudManager.lastiCloudAccount == nil {
                CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
            }
            Model.searchableIndex(CSSearchableIndex.default()) {
                PersistedOptions.lastRanVersion = currentBuild
            }
		}
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

	private static func performSave() {

        let index = CSSearchableIndex.default()

        let itemsToDelete = Set(drops.filter { $0.needsDeletion })
        #if MAINAPP
        MirrorManager.removeItems(items: itemsToDelete)
        #endif

        let removedUuids = itemsToDelete.map { $0.uuid }
        index.deleteSearchableItems(withIdentifiers: removedUuids.map { $0.uuidString }) { error in
            if let error = error {
                log("Error while deleting search indexes \(error.localizedDescription)")
            }
        }
        
        drops.removeAll { $0.needsDeletion }

        let saveableItems: ContiguousArray = drops.filter { $0.goodToSave }
        let itemsToWrite = saveableItems.filter { $0.flags.contains(.needsSaving) }
        let searchableItems = itemsToWrite.map { $0.searchableItem }
        reIndex(items: searchableItems, in: index)

		let uuidsToEncode = Set(itemsToWrite.map { i -> UUID in
            i.flags.remove(.isBeingCreatedBySync)
            i.flags.remove(.needsSaving)
            return i.uuid
		})
        
        isSaving = true
        needsAnotherSave = false

        NotificationCenter.default.post(name: .ModelDataUpdated, object: ["updated": uuidsToEncode, "removed": removedUuids])

		saveQueue.async {
			do {
				try coordinatedSave(allItems: saveableItems, dirtyUuids: uuidsToEncode)
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
                    saveComplete(wasIndexOnly: false)
				}
			}
		}
	}

    static func saveIndexOnly() {
        let itemsToSave: ContiguousArray = drops.filter { $0.goodToSave }
        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil)
		saveQueue.async {
			do {
				_ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: [])
				log("Saved index only")
			} catch {
				log("Warning: Error while committing index to disk: (\(error.finalDescription))")
			}
			DispatchQueue.main.async {
                saveComplete(wasIndexOnly: true)
			}
		}
	}

    private static var commitQueue = ContiguousArray<ArchivedItem>()
	static func commitItem(item: ArchivedItem) {
        item.flags.remove(.isBeingCreatedBySync)
        item.flags.remove(.needsSaving)
        commitQueue.append(item)
        
        reIndex(items: [item.searchableItem], in: CSSearchableIndex.default())
		
        saveQueue.async {
            var nextItemUUIDs = Set<UUID>()
            var itemsToSave = ContiguousArray<ArchivedItem>()
            DispatchQueue.main.sync {
                nextItemUUIDs = Set(commitQueue.filter { !$0.needsDeletion }.map { $0.uuid })
                commitQueue.removeAll()
                itemsToSave = drops.filter { $0.goodToSave }
            }
            if nextItemUUIDs.isEmpty {
                return
            }
            do {
                _ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: nextItemUUIDs)
                log("Ingest completed for items (\(nextItemUUIDs)) and committed to disk")
            } catch {
                log("Warning: Error while committing item to disk: (\(error.finalDescription))")
            }
		}
	}
    
	private static func coordinatedSave(allItems: ContiguousArray<ArchivedItem>, dirtyUuids: Set<UUID>) throws {
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
                let p = url.path
				if !fm.fileExists(atPath: p) {
					try fm.createDirectory(atPath: p, withIntermediateDirectories: true, attributes: nil)
				}

				var uuidData = Data()
				uuidData.reserveCapacity(allItems.count * 16)
				for item in allItems {
					let u = item.uuid
					let t = u.uuid
					uuidData.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
					if dirtyUuids.contains(u) {
                        let finalPath = url.appendingPathComponent(u.uuidString)
                        try saveEncoder.encode(item).write(to: finalPath)
					}
				}
				try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

				if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String], (filesInDir.count - 1) > allItems.count { // at least one old file exists, let's find it
                    let uuidStrings = Set(allItems.map { $0.uuid.uuidString })
                    for file in filesInDir where !uuidStrings.contains(file) && file != "uuids" { // old file
                        log("Removing save file for non-existent item: \(file)")
                        let finalPath = url.appendingPathComponent(file)
                        try? fm.removeItem(at: finalPath)
                    }
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
    
    static func detectExternalChanges() {
        for item in drops where !item.needsDeletion { // partial deletes
            let componentsToDelete = item.components.filter { $0.needsDeletion }
            if !componentsToDelete.isEmpty {
                item.components.removeAll { $0.needsDeletion }
                for c in componentsToDelete {
                    c.deleteFromStorage()
                }
                item.needsReIngest = true
            }
        }
        let itemsToDelete = drops.filter { $0.needsDeletion }
        if !itemsToDelete.isEmpty {
            delete(items: itemsToDelete) // will also save
        }
        
        for drop in drops where drop.needsReIngest && !drop.needsDeletion && drop.loadingProgress == nil {
            drop.reIngest()
        }
    }
    
    static func sendToTop(items: [ArchivedItem]) {
        let uuids = Set(items.map { $0.uuid })
        let cut = drops.filter { uuids.contains($0.uuid) }
        if cut.isEmpty { return }
        
        drops.removeAll { uuids.contains($0.uuid) }
        drops.insert(contentsOf: cut, at: 0)

        saveIndexOnly()
    }
}
