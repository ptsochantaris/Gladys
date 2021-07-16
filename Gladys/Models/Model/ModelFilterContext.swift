//
//  ModelFilterContext.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 25/04/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CoreSpotlight
#if os(iOS)
import UIKit
#endif

struct SectionIdentifier: Hashable {
    let label: ModelFilterContext.LabelToggle?
}

struct ItemIdentifier: Hashable {
    let label: ModelFilterContext.LabelToggle?
    let uuid: UUID
}

protocol ModelFilterContextDelegate: AnyObject {
    func modelFilterContextChanged(_ modelFilterContext: ModelFilterContext, animate: Bool)
}

final class ModelFilterContext {
    
    enum UpdateType {
        case none, instant, animated
    }
    
    enum DisplayMode: Int, Codable {
        case collapsed, scrolling, full
    }
    
    enum GroupingMode: Int {
        case flat, byLabel
        
        var imageName: String {
            switch self {
            case .flat:
                return "square.grid.3x3"
            case .byLabel:
                return "square.grid.3x1.below.line.grid.1x2"
            }
        }
    }
    
    weak var delegate: ModelFilterContextDelegate?
    
    var groupingMode = GroupingMode.flat
    var isFilteringText = false

    private var modelFilter: String?
    private var cachedFilteredDrops: ContiguousArray<ArchivedItem>?

    init() {
        rebuildLabels()
    }

    var sizeOfVisibleItemsInBytes: Int64 {
        return filteredDrops.reduce(0, { $0 + $1.sizeInBytes })
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

    var text: String? {
        get {
            return modelFilter
        }
        set {
            let v = newValue == "" ? nil : newValue
            if modelFilter != v {
                modelFilter = v
                updateFilter(signalUpdate: .animated)
            }
        }
    }
    
    func nearestUnfilteredIndexForFilteredIndex(_ index: Int, checkForWeirdness: Bool) -> Int {
        if isFiltering {
            if index >= filteredDrops.count {
                if let closestItem = filteredDrops.last, let i = Model.firstIndexOfItem(with: closestItem.uuid) {
                    let ret = i+1
                    if checkForWeirdness, ret >= filteredDrops.count {
                        return -1
                    } else {
                        return ret
                    }
                }
                return 0
            } else {
                let closestItem = filteredDrops[index]
                return Model.firstIndexOfItem(with: closestItem.uuid) ?? 0
            }
        } else {
            if checkForWeirdness, index >= filteredDrops.count {
                return -1
            }
            return index
        }
    }
    
    func setDisplayMode(to displayMode: DisplayMode, for names: Set<String>?, setAsPreference: Bool) {
        if let names = names {
            labelToggles = labelToggles.map {
                let effectiveName = $0.emptyChecker ? ModelFilterContext.LabelToggle.noNameTitle : $0.name
                if names.contains(effectiveName) {
                    var newToggle = $0
                    newToggle.displayMode = displayMode
                    if setAsPreference, displayMode == .scrolling || displayMode == .full {
                        newToggle.preferredDisplayMode = displayMode
                    }
                    return newToggle
                } else {
                    return $0
                }
            }
        } else {
            labelToggles = labelToggles.map {
                var newToggle = $0
                newToggle.displayMode = displayMode
                if setAsPreference, displayMode == .scrolling || displayMode == .full {
                    newToggle.preferredDisplayMode = displayMode
                }
                return newToggle
            }
        }
    }
    
    func labels(for displayMode: DisplayMode) -> [LabelToggle] {
        return labelToggles.filter { $0.displayMode == displayMode }
    }
    
    func enableLabelsByName(_ names: Set<String>) {
        labelToggles = labelToggles.map {
            var newToggle = $0
            let effectiveName = $0.emptyChecker ? ModelFilterContext.LabelToggle.noNameTitle : $0.name
            newToggle.enabled = names.contains(effectiveName)
            return newToggle
        }
    }
    
    static private func terms(for text: String?) -> [String]? {
        guard let text = text?.replacingOccurrences(of: "”", with: "\"").replacingOccurrences(of: "“", with: "\"") else { return nil }

        var terms = [String]()
        do {
            let regex = try NSRegularExpression(pattern: "(\\b\\S+?\\b|\\B\\\".+?\\\"\\B)")
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).forEach {
                guard let r = Range($0.range, in: text) else { return }
                let s = text[r]
                let term = s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let criterion = "\"*\(term)*\"cd"
                terms.append("title == \(criterion) || textContent == \(criterion) || contentDescription == \(criterion) || keywords == \(criterion)")
            }
        } catch {
            log("Warning regex error: \(error.localizedDescription)")
        }
        return terms
    }

    @discardableResult
    func updateFilter(signalUpdate: UpdateType, forceAnnounce: Bool = false) -> Bool {
        
        let previousFilteredDrops = filteredDrops
        
        // label pass
        
        let enabledToggles = labelToggles.filter { $0.enabled }
        let postLabelDrops: ContiguousArray<ArchivedItem>
        if enabledToggles.isEmpty {
            postLabelDrops = Model.drops
            
        } else if PersistedOptions.exclusiveMultipleLabels {
            let expectedCount = enabledToggles.count
            postLabelDrops = Model.drops.filter { item in
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
            postLabelDrops = Model.drops.filter { item in
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
        
        // text pass

        if let terms = ModelFilterContext.terms(for: modelFilter), !terms.isEmpty {
            var replacementResults = Set<UUID>()

            let lock = DispatchSemaphore(value: 0)
            let queryString: String
            if terms.count > 1 {
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
                items.forEach {
                    if let uuid = UUID(uuidString: $0.uniqueIdentifier) {
                        replacementResults.insert(uuid)
                    }
                }
            }
            q.completionHandler = { error in
                if let error = error {
                    log("Search error: \(error.finalDescription)")
                }
                lock.signal()
            }
            isFilteringText = true
            q.start()
            lock.wait()

            cachedFilteredDrops = postLabelDrops.filter { replacementResults.contains($0.uuid) }
        } else {
            isFilteringText = false
            cachedFilteredDrops = postLabelDrops
        }

        let changesToVisibleItems = forceAnnounce || previousFilteredDrops != filteredDrops
        if changesToVisibleItems {
            Model.updateBadge()
            if signalUpdate != .none {

                self.delegate?.modelFilterContextChanged(self, animate: signalUpdate == .animated)

                #if os(iOS)
                if isFilteringText && UIAccessibility.isVoiceOverRunning {
                    let resultString: String
                    let c = filteredDrops.count
                    if c == 0 {
                        resultString = "No results"
                    } else if c == 1 {
                        resultString = "One result"
                    } else {
                        resultString = "\(filteredDrops.count) results"
                    }
                    UIAccessibility.post(notification: .announcement, argument: resultString)
                }
                #endif
            }
        }

        return changesToVisibleItems
    }
        
    var enabledLabelsForItems: [String] {
        return labelToggles.compactMap { $0.enabled && !$0.emptyChecker ? $0.name : nil }
    }

    var enabledLabelsForTitles: [String] {
        return labelToggles.compactMap { $0.enabled ? $0.name : nil }
    }
    
    var eligibleDropsForExport: ContiguousArray<ArchivedItem> {
        let items = PersistedOptions.exportOnlyVisibleItems ? filteredDrops : Model.drops // copy
        return items.filter { $0.goodToSave }
    }
    
    var labelToggles = [LabelToggle]()
    
    func applyLabelConfig(from newToggles: [LabelToggle]) {
        labelToggles = labelToggles.map { existingToggle in
            if let newToggle = newToggles.first(where: { $0.name == existingToggle.name }) {
                return LabelToggle(name: newToggle.name, count: existingToggle.count, enabled: newToggle.enabled, displayMode: newToggle.displayMode, preferredDisplayMode: newToggle.preferredDisplayMode, emptyChecker: newToggle.emptyChecker)
            } else {
                return existingToggle
            }
        }
    }

    struct LabelToggle: Hashable, Codable {
        
        enum Section {
            case recent(labels: [String], title: String)
            case filtered(labels: [String], title: String)
            
            static var latestLabels: [String] {
                get {
                    return UserDefaults.standard.object(forKey: "latestLabels") as? [String] ?? []
                }
                set {
                    UserDefaults.standard.set(newValue, forKey: "latestLabels")
                }
            }

            var labels: [String] {
                switch self {
                case .filtered(let labels, _), .recent(let labels, _):
                    return labels
                }
            }

            var title: String {
                switch self {
                case .filtered(_, let title), .recent(_, let title):
                    return title
                }
            }
        }

        static let noNameTitle = "Items with no labels"
        
        let name: String
        let count: Int
        var enabled: Bool
        var displayMode: DisplayMode
        var preferredDisplayMode: DisplayMode
        let emptyChecker: Bool
        
        static func == (lhs: LabelToggle, rhs: LabelToggle) -> Bool {
            return lhs.emptyChecker == rhs.emptyChecker
            && lhs.enabled == rhs.enabled
            && lhs.displayMode == rhs.displayMode
            && lhs.name == rhs.name
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(emptyChecker)
            hasher.combine(enabled)
            hasher.combine(displayMode)
            hasher.combine(name)
        }

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
    
    var enabledToggles: [LabelToggle] {
        var res: [ModelFilterContext.LabelToggle]
        if isFilteringLabels {
            res = labelToggles.filter { $0.enabled }
        } else {
            res = labelToggles
        }
        if let i = res.firstIndex(where: { $0.emptyChecker }), i != 0 {
            let item = res.remove(at: i)
            res.insert(item, at: 0)
        }
        return res
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
        var counts = [String: Int]()
        counts.reserveCapacity(labelToggles.count)
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

        let previousList = labelToggles
        labelToggles = counts.map { (label, count) in
            if let previousItem = previousList.first(where: { $0.name == label }) {
                let previousEnabled = previousItem.enabled
                let previousDisplayMode = previousItem.displayMode
                let previousPreferredMode = previousItem.preferredDisplayMode
                return LabelToggle(name: label, count: count, enabled: previousEnabled, displayMode: previousDisplayMode, preferredDisplayMode: previousPreferredMode, emptyChecker: false)
            } else {
                return LabelToggle(name: label, count: count, enabled: false, displayMode: .collapsed, preferredDisplayMode: .scrolling, emptyChecker: false)
            }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        if !labelToggles.isEmpty && noLabelCount > 0 {
            let label = ModelFilterContext.LabelToggle.noNameTitle
            let t: LabelToggle
            if let previousItem = previousList.first(where: { $0.name == label }) {
                let previousEnabled = previousItem.enabled
                let previousDisplayMode = previousItem.displayMode
                let previousPreferredMode = previousItem.preferredDisplayMode
                t = LabelToggle(name: label, count: noLabelCount, enabled: previousEnabled, displayMode: previousDisplayMode, preferredDisplayMode: previousPreferredMode, emptyChecker: true)
            } else {
                t = LabelToggle(name: label, count: noLabelCount, enabled: false, displayMode: .collapsed, preferredDisplayMode: .scrolling, emptyChecker: true)
            }
            labelToggles.append(t)
        }
    }

    func updateLabel(_ label: LabelToggle) {
        if let i = labelToggles.firstIndex(where: { $0.name == label.name }) {
            labelToggles[i] = label
        }
    }

    func renameLabel(_ label: String, to newLabel: String) {
        let wasEnabled = labelToggles.first { $0.name == label }?.enabled ?? false
        
        Model.drops.forEach { i in
            if let index = i.labels.firstIndex(of: label) {
                if i.labels.contains(newLabel) {
                    i.labels.remove(at: index)
                } else {
                    i.labels[index] = newLabel
                }
                i.needsCloudPush = true
                i.flags.insert(.needsSaving)
            }
        }

        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels
        
        if wasEnabled, let i = labelToggles.firstIndex(where: { $0.name == newLabel }) {
            var l = labelToggles[i]
            l.enabled = true
            labelToggles[i] = l
        }
        
        NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
        
        Model.save()
    }
    
    func removeLabel(_ label: String) {
        Model.drops.forEach { i in
            if i.labels.contains(label) {
                i.labels.removeAll { $0 == label }
                i.needsCloudPush = true
                i.flags.insert(.needsSaving)
            }
        }
        
        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels
        NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
        Model.save()
    }
}
