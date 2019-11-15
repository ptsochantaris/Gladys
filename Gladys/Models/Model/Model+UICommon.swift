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

final class ModelFilterContext {

    private var modelFilter: String?
    private var currentFilterQuery: CSSearchQuery?
    private var cachedFilteredDrops: [ArchivedDropItem]?
    
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

    var filteredDrops: [ArchivedDropItem] {
        return cachedFilteredDrops ?? Model.drops
    }

    var filter: String? {
        get {
            return modelFilter
        }
        set {
            if modelFilter == newValue { return }
            forceUpdateFilter(with: newValue, signalUpdate: true)
        }
    }
    
    var threadSafeFilteredDrops: [ArchivedDropItem] {
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
    
    func nearestUnfilteredIndexForFilteredIndex(_ index: Int) -> Int {
        guard isFiltering else {
            return index
        }
        if filteredDrops.count == 0 {
            return 0
        }
        let closestItem: ArchivedDropItem
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
    func forceUpdateFilter(with newValue: String? = nil, signalUpdate: Bool) -> Bool {
        currentFilterQuery = nil
        modelFilter = newValue ?? modelFilter

        let previouslyVisibleUuids = filteredDrops.map { $0.uuid }
        var filtering = false

        if let terms = Model.terms(for: filter), !terms.isEmpty {

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
    
    private var postLabelDrops: [ArchivedDropItem] {
        let enabledToggles = labelToggles.filter { $0.enabled }
        if enabledToggles.isEmpty { return Model.drops }

        if PersistedOptions.exclusiveMultipleLabels {
            let expectedCount = enabledToggles.count
            return Model.drops.filter { item in
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
            return Model.drops.filter { item in
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
    
    func resetEverything() {
        modelFilter = nil
        cachedFilteredDrops = nil
        Model.resetEverything()
    }
    
    var enabledLabelsForItems: [String] {
        return labelToggles.compactMap { $0.enabled && !$0.emptyChecker ? $0.name : nil }
    }

    var enabledLabelsForTitles: [String] {
        return labelToggles.compactMap { $0.enabled ? $0.name : nil }
    }
    
    var eligibleDropsForExport: [ArchivedDropItem] {
        let items = PersistedOptions.exportOnlyVisibleItems ? threadSafeFilteredDrops : Model.threadSafeDrops
        return items.filter { $0.goodToSave }
    }
    
    var labelToggles = [LabelToggle]()

    struct LabelToggle {
        
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
            if item.labels.count == 0 {
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
        if labelToggles.count > 0 {
            labelToggles.sort { $0.name < $1.name }

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
    
    func removeLabel(_ label : String) {
        var itemsNeedingReIndex = [ArchivedDropItem]()
        for i in Model.drops {
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
                    Model.save()
                }
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
				//Model.forceUpdateFilter(signalUpdate: false)
				Model.save()
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

	static fileprivate func resetEverything() {
		drops.filter { !$0.isImportedShare }.forEach { $0.delete() }
		drops.removeAll { !$0.isImportedShare }
        #if MAINAPP
        deleteMirror {}
        #endif
		clearCaches()
		save()
        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil) // save will not post that, as it's all deletes
	}

	static func removeImportedShares() {
		drops.removeAll { $0.isImportedShare }
		save()
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

	static var itemsIAmSharing: [ArchivedDropItem] {
		return drops.filter { $0.shareMode == .sharing }
	}

	static func duplicate(item: ArchivedDropItem) {
		if let previousIndex = drops.firstIndex(of: item) {
			let newItem = ArchivedDropItem(cloning: item)
			drops.insert(newItem, at: previousIndex+1)
            save()
		}
	}

    static func delete(items: [ArchivedDropItem]) {

        let uuidsToRemove = Set(items.map { $0.uuid })
        drops.removeAll { uuidsToRemove.contains($0.uuid) }
        NotificationCenter.default.post(name: .ItemsRemoved, object: uuidsToRemove)
        
        for item in items {
            if item.shouldDisplayLoading {
                item.cancelIngest()
            }
            item.delete()
        }

        save()
	}

	static var doneIngesting: Bool {
		return !drops.contains { ($0.needsReIngest && !$0.isDeleting) || ($0.loadingProgress != nil && $0.loadingError == nil) }
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
        
		saveQueue.async {
			do {
				try coordinatedSave(allItems: itemsToSave, dirtyUuids: uuidsToEncode)
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
                    if !uuidsToEncode.isEmpty {
                        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil)
                    }
					saveComplete()
				}
			}
		}
	}

    static func saveIndexOnly(from requester: Any?) {
		let itemsToSave = drops.filter { $0.goodToSave }
		saveQueue.async {
			do {
				_ = try coordinatedSave(allItems: itemsToSave, dirtyUuids: [])
				log("Saved index only")
			} catch {
				log("Warning: Error while committing index to disk: (\(error.finalDescription))")
			}
			DispatchQueue.main.async {
                NotificationCenter.default.post(name: .ModelDataUpdated, object: requester)
				saveIndexComplete()
			}
		}
	}

    private static var commitQueue = [ArchivedDropItem]()
	static func commitItem(item: ArchivedDropItem) {
		item.isBeingCreatedBySync = false
		item.needsSaving = false
        commitQueue.append(item)
		saveQueue.async {
            var nextItemUUIDs = [UUID]()
            var itemsToSave = [ArchivedDropItem]()
            DispatchQueue.main.sync {
                nextItemUUIDs = commitQueue.filter { !$0.isDeleting }.map { $0.uuid }
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
    
    static func detectExternalChanges() {
        for item in drops.filter({ !$0.needsDeletion }) { // partial deletes
            let componentsToDelete = item.typeItems.filter { $0.needsDeletion }
            if componentsToDelete.count > 0 {
                item.typeItems = item.typeItems.filter { !$0.needsDeletion }
                for c in componentsToDelete {
                    c.deleteFromStorage()
                }
                item.needsReIngest = true
            }
        }
        let itemsToDelete = drops.filter { $0.needsDeletion }
        if itemsToDelete.count > 0 {
            delete(items: itemsToDelete) // will also save
        }
        
        drops.filter { $0.needsReIngest && $0.loadingProgress == nil && !$0.isDeleting }.forEach { $0.reIngest() }
    }
    
    static func sendToTop(items: [ArchivedDropItem]) {
        let uuids = Set(items.map { $0.uuid })
        let cut = drops.filter { uuids.contains($0.uuid) }
        if cut.isEmpty { return }
        
        drops.removeAll { uuids.contains($0.uuid) }
        drops.insert(contentsOf: cut, at: 0)

        saveIndexOnly(from: nil)
    }
}
