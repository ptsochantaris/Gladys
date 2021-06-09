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

protocol ModelFilterContextDelegate: AnyObject {
    func modelFilterContextChanged(_ modelFilterContext: ModelFilterContext, animate: Bool)
}

final class ModelFilterContext {
    
    enum UpdateType {
        case none, instant, animated
    }
    
    enum GroupingMode: Int {
        case flat, byLabel, byLabelScrollable
        
        var imageName: String {
            switch self {
            case .flat:
                return "square.grid.3x3"
            case .byLabel:
                return "square.grid.3x3.fill.square"
            case .byLabelScrollable:
                return "square.grid.3x1.below.line.grid.1x2"
            }
        }
    }
    
    weak var delegate: ModelFilterContextDelegate?
    
    var groupingMode = GroupingMode.flat

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
    
    func enableLabelsByName(_ names: Set<String>) {
        labelToggles = labelToggles.map {
            var newToggle = $0
            let effectiveName = $0.emptyChecker ? ModelFilterContext.LabelToggle.noNameTitle : $0.name
            newToggle.enabled = names.contains(effectiveName)
            return newToggle
        }
    }

    func collapseLabelsByName(_ names: Set<String>) {
        labelToggles = labelToggles.map {
            var newToggle = $0
            let effectiveName = $0.emptyChecker ? ModelFilterContext.LabelToggle.noNameTitle : $0.name
            if names.contains(effectiveName) {
                newToggle.collapsed = true
            } else {
                newToggle.collapsed = $0.collapsed
            }
            return newToggle
        }
    }
    
    var collapsedLabels: [LabelToggle] {
        return labelToggles.filter { $0.collapsed }
    }
    
    func expandAllLabels() {
        labelToggles = labelToggles.map {
            return LabelToggle(name: $0.name, count: $0.count, enabled: $0.enabled, collapsed: false, emptyChecker: $0.emptyChecker)
        }
    }

    func collapseAllLabels() {
        labelToggles = labelToggles.map {
            return LabelToggle(name: $0.name, count: $0.count, enabled: $0.enabled, collapsed: true, emptyChecker: $0.emptyChecker)
        }
    }

    func expandLabelsByName(_ names: Set<String>) {
        labelToggles = labelToggles.map {
            var newToggle = $0
            let effectiveName = $0.emptyChecker ? ModelFilterContext.LabelToggle.noNameTitle : $0.name
            if names.contains(effectiveName) {
                newToggle.collapsed = false
            } else {
                newToggle.collapsed = $0.collapsed
            }
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
    func updateFilter(signalUpdate: UpdateType) -> Bool {
        currentFilterQuery = nil

        let previousFilteredDrops = filteredDrops
        var filtering = false

        if let terms = ModelFilterContext.terms(for: modelFilter), !terms.isEmpty {

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
        if changesToVisibleItems {
            Model.updateBadge()
            if signalUpdate != .none {

                self.delegate?.modelFilterContextChanged(self, animate: signalUpdate == .animated)

                #if os(iOS)
                if filtering && UIAccessibility.isVoiceOverRunning {
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
        let items = PersistedOptions.exportOnlyVisibleItems ? filteredDrops : Model.drops // copy
        return items.filter { $0.goodToSave }
    }
    
    var labelToggles = [LabelToggle]()

    struct LabelToggle: Hashable {
        
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
        var collapsed: Bool
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
            // TODO optimise
            let previousEnabled = previous.contains { $0.enabled && $0.name == label }
            let previousCollapsed = previous.contains { $0.collapsed && $0.name == label }
            let toggle = LabelToggle(name: label, count: count, enabled: previousEnabled, collapsed: previousCollapsed, emptyChecker: false)
            labelToggles.append(toggle)
        }
        if !labelToggles.isEmpty {
            labelToggles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let name = ModelFilterContext.LabelToggle.noNameTitle
            let previousEnabled = previous.contains { $0.enabled && $0.name == name }
            let previousCollapsed = previous.contains { $0.collapsed && $0.name == name }
            labelToggles.append(LabelToggle(name: name, count: noLabelCount, enabled: previousEnabled, collapsed: previousCollapsed, emptyChecker: true))
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
