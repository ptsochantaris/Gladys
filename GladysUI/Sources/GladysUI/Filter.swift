import CoreSpotlight
import Foundation
#if os(iOS)
    import UIKit
#endif
import GladysCommon

public struct SectionIdentifier: Hashable {
    public let label: Filter.Toggle?
    public init(label: Filter.Toggle?) {
        self.label = label
    }
}

public struct ItemIdentifier: Hashable {
    public let label: Filter.Toggle?
    public let uuid: UUID
    public init(label: Filter.Toggle?, uuid: UUID) {
        self.label = label
        self.uuid = uuid
    }
}

public protocol FilterDelegate: AnyObject {
    func modelFilterContextChanged(_ modelFilterContext: Filter, animate: Bool)
}

@MainActor
public final class Filter {
    public enum UpdateType {
        case none, instant, animated
    }

    public enum DisplayMode: Int, Codable {
        case collapsed, scrolling, full
    }

    public enum GroupingMode: Int {
        case flat, byLabel

        public var imageName: String {
            switch self {
            case .flat:
                return "square.grid.3x3"
            case .byLabel:
                return "square.grid.3x1.below.line.grid.1x2"
            }
        }
    }

    public weak var delegate: FilterDelegate?

    public var groupingMode = GroupingMode.flat
    public var isFilteringText = false

    private var modelFilter: String?
    private var cachedFilteredDrops: ContiguousArray<ArchivedItem>?

    public init() {
        rebuildLabels()
    }

    public func sizeOfVisibleItemsInBytes() async -> Int64 {
        let snapshot = filteredDrops
        return await Task.detached {
            snapshot.reduce(0) { $0 + $1.sizeInBytes }
        }.value
    }

    public var isFilteringLabels: Bool {
        labelToggles.contains { $0.active }
    }

    public var isFiltering: Bool {
        isFilteringText || isFilteringLabels
    }

    public var filteredDrops: ContiguousArray<ArchivedItem> {
        if cachedFilteredDrops == nil { // this array must always be separate from updates from the model
            cachedFilteredDrops = DropStore.allDrops
        }
        return cachedFilteredDrops!
    }

    public var text: String? {
        get {
            modelFilter
        }
        set {
            let v = newValue == "" ? nil : newValue
            if modelFilter != v {
                modelFilter = v
                _ = update(signalUpdate: .animated)
            }
        }
    }

    public func nearestUnfilteredIndexForFilteredIndex(_ index: Int, checkForWeirdness: Bool) -> Int {
        if isFiltering {
            if index >= filteredDrops.count {
                if let closestItem = filteredDrops.last, let i = DropStore.indexOfItem(with: closestItem.uuid) {
                    let ret = i + 1
                    if checkForWeirdness, ret >= filteredDrops.count {
                        return -1
                    } else {
                        return ret
                    }
                }
                return 0
            } else {
                let closestItem = filteredDrops[index]
                return DropStore.indexOfItem(with: closestItem.uuid) ?? 0
            }
        } else {
            if checkForWeirdness, index >= filteredDrops.count {
                return -1
            }
            return index
        }
    }

    public func setDisplayMode(to displayMode: DisplayMode, for names: Set<String>?, setAsPreference: Bool) {
        if let names {
            labelToggles = labelToggles.map {
                let effectiveName = $0.function.displayText
                if names.contains(effectiveName) {
                    var newToggle = $0
                    newToggle.currentDisplayMode = displayMode
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
                newToggle.currentDisplayMode = displayMode
                if setAsPreference, displayMode == .scrolling || displayMode == .full {
                    newToggle.preferredDisplayMode = displayMode
                }
                return newToggle
            }
        }
    }

    public func labels(for displayMode: DisplayMode) -> [Toggle] {
        labelToggles.filter { $0.currentDisplayMode == displayMode }
    }

    public func enableLabelsByName(_ names: Set<String>) {
        labelToggles = labelToggles.map {
            var newToggle = $0
            newToggle.active = names.contains($0.function.displayText)
            return newToggle
        }
    }

    private static let regex = try! NSRegularExpression(pattern: "(\\b\\S+?\\b|\\B\\\".+?\\\"\\B)")

    private static func terms(for text: String?) -> [String]? {
        guard let text = text?.replacingOccurrences(of: "”", with: "\"").replacingOccurrences(of: "“", with: "\"") else { return nil }

        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> String? in
            guard let r = Range(match.range, in: text) else { return nil }
            let s = text[r]
            let term = s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let criterion = "\"*\(term)*\"cd"
            return "title == \(criterion) || textContent == \(criterion) || contentDescription == \(criterion) || keywords == \(criterion)"
        }
    }

    public func countItems(for toggle: Toggle) -> Int {
        filteredDrops.reduce(0) {
            switch toggle.function {
            case let .userLabel(text):
                if $1.labels.contains(text) {
                    return $0 + 1
                }
            case .unlabeledItems:
                if $1.labels.isEmpty {
                    return $0 + 1
                }
            case .recentlyAddedItems:
                if $1.isRecentlyAdded {
                    return $0 + 1
                }
            }
            return $0
        }
    }
    
    private func findIds(for queryString: String) -> Set<UUID> {
        var replacementResults = Set<UUID>()
        
        let q = CSSearchQuery(queryString: queryString, attributes: nil)
        q.foundItemsHandler = { items in
            for item in items {
                if let uuid = UUID(uuidString: item.uniqueIdentifier) {
                    replacementResults.insert(uuid)
                }
            }
        }
        let lock = NSLock()
        lock.lock()
        q.completionHandler = { error in
            if let error {
                log("Search error: \(error.finalDescription)")
            }
            lock.unlock()
        }
        q.start()
        if lock.lock(before: Date(timeIntervalSinceNow: 10)) {
        } else {
            q.cancel()
        }
        lock.unlock()
        return replacementResults
    }

    @discardableResult
    public func update(signalUpdate: UpdateType, forceAnnounce: Bool = false) -> Bool {
        let previousFilteredDrops = filteredDrops

        // label pass

        let enabledToggles = labelToggles.filter(\.active)
        let postLabelDrops: ContiguousArray<ArchivedItem>
        if enabledToggles.isEmpty {
            postLabelDrops = DropStore.allDrops

        } else if PersistedOptions.exclusiveMultipleLabels {
            let expectedCount = enabledToggles.count
            postLabelDrops = DropStore.allDrops.filter { item in
                var matchCount = 0
                for toggle in enabledToggles {
                    switch toggle.function {
                    case .unlabeledItems: if item.labels.isEmpty { matchCount += 1 }
                    case .recentlyAddedItems: if item.isRecentlyAdded { matchCount += 1 }
                    case let .userLabel(text): if item.labels.contains(text) { matchCount += 1 }
                    }
                }
                return matchCount == expectedCount
            }

        } else {
            postLabelDrops = DropStore.allDrops.filter { item in
                for toggle in enabledToggles {
                    switch toggle.function {
                    case .unlabeledItems: if item.labels.isEmpty { return true }
                    case .recentlyAddedItems: if item.isRecentlyAdded { return true }
                    case let .userLabel(text): if item.labels.contains(text) { return true }
                    }
                }
                return false
            }
        }

        // text pass

        if let terms = Filter.terms(for: modelFilter), !terms.isEmpty {
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

            isFilteringText = true
            let replacementResults = findIds(for: queryString)
            cachedFilteredDrops = postLabelDrops.filter { replacementResults.contains($0.uuid) }
        } else {
            isFilteringText = false
            cachedFilteredDrops = postLabelDrops
        }

        let changesToVisibleItems = forceAnnounce || previousFilteredDrops != filteredDrops
        if changesToVisibleItems {
            Model.updateBadge()
            if signalUpdate != .none {
                delegate?.modelFilterContextChanged(self, animate: signalUpdate == .animated)

                #if os(macOS)
                #else
                    if isFilteringText, UIAccessibility.isVoiceOverRunning {
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

    public var enabledLabelsForItems: [String] {
        labelToggles.compactMap {
            if $0.active {
                if case let .userLabel(name) = $0.function {
                    return name
                }
            }
            return nil
        }
    }

    public var enabledLabelsForTitles: [String] {
        labelToggles.compactMap { $0.active ? $0.function.displayText : nil }
    }

    public var eligibleDropsForExport: ContiguousArray<ArchivedItem> {
        let items = PersistedOptions.exportOnlyVisibleItems ? filteredDrops : DropStore.allDrops // copy
        return items.filter(\.goodToSave)
    }

    public var labelToggles = [Toggle]()

    public func applyLabelConfig(from newToggles: [Toggle]) {
        labelToggles = labelToggles.map { existingToggle in
            if let newToggle = newToggles.first(where: { $0.function == existingToggle.function }) {
                return Toggle(function: newToggle.function, count: existingToggle.count, active: newToggle.active, currentDisplayMode: newToggle.currentDisplayMode, preferredDisplayMode: newToggle.preferredDisplayMode)
            } else {
                return existingToggle
            }
        }
    }

    public struct Toggle: Hashable, Codable {
        public enum Section {
            case recent(labels: [String], title: String)
            case filtered(labels: [String], title: String)

            public static var latestLabels: [String] {
                get {
                    UserDefaults.standard.object(forKey: "latestLabels") as? [String] ?? []
                }
                set {
                    UserDefaults.standard.set(newValue, forKey: "latestLabels")
                }
            }

            public var labels: [String] {
                switch self {
                case let .filtered(labels, _), let .recent(labels, _):
                    return labels
                }
            }

            public var title: String {
                switch self {
                case let .filtered(_, title), let .recent(_, title):
                    return title
                }
            }
        }

        public enum Function: Hashable, Codable {
            case userLabel(String)
            case recentlyAddedItems
            case unlabeledItems

            public static func == (lhs: Function, rhs: Function) -> Bool {
                switch lhs {
                case let .userLabel(leftText):
                    switch rhs {
                    case let .userLabel(rightText):
                        return leftText.localizedCaseInsensitiveCompare(rightText) == .orderedSame
                    case .recentlyAddedItems, .unlabeledItems:
                        return false
                    }
                case .recentlyAddedItems:
                    if case .recentlyAddedItems = rhs { return true } else { return false }
                case .unlabeledItems:
                    if case .unlabeledItems = rhs { return true } else { return false }
                }
            }

            public var displayText: String {
                switch self {
                case let .userLabel(name): return name
                case .unlabeledItems: return "Items with no labels"
                case .recentlyAddedItems: return "Recently added"
                }
            }
        }

        public let function: Function
        public let count: Int
        public var active: Bool
        public var currentDisplayMode: DisplayMode
        public var preferredDisplayMode: DisplayMode

        public init(function: Function, count: Int, active: Bool, currentDisplayMode: DisplayMode, preferredDisplayMode: DisplayMode) {
            self.function = function
            self.count = count
            self.active = active
            self.currentDisplayMode = currentDisplayMode
            self.preferredDisplayMode = preferredDisplayMode
        }

        public static func == (lhs: Toggle, rhs: Toggle) -> Bool {
            lhs.function == rhs.function
                && lhs.active == rhs.active
                && lhs.currentDisplayMode == rhs.currentDisplayMode
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(function)
            hasher.combine(active)
            hasher.combine(currentDisplayMode)
        }

        public enum State {
            case none, some, all
            public var accessibilityValue: String? {
                switch self {
                case .none: return nil
                case .some: return "Applied to some selected items"
                case .all: return "Applied to all selected items"
                }
            }
        }

        @MainActor
        public func toggleState(across uuids: [UUID]?) -> State {
            guard case let .userLabel(name) = function else {
                return .none
            }
            let n = uuids?.reduce(0) { total, uuid -> Int in
                if let item = DropStore.item(uuid: uuid), item.labels.contains(name) {
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

    public var enabledToggles: [Toggle] {
        var res: [Filter.Toggle]
        if isFilteringLabels {
            res = labelToggles.filter(\.active)
        } else {
            res = labelToggles
        }

        if let i = res.firstIndex(where: { $0.function == .unlabeledItems }), i != 0 {
            let item = res.remove(at: i)
            res.insert(item, at: 0)
        }

        if let i = res.firstIndex(where: { $0.function == .recentlyAddedItems }), i != 0 {
            let item = res.remove(at: i)
            res.insert(item, at: 0)
        }
        return res
    }

    public func disableAllLabels() {
        labelToggles = labelToggles.map {
            if $0.active {
                var l = $0
                l.active = false
                return l
            } else {
                return $0
            }
        }
    }

    public func rebuildRecentlyAdded() -> Bool {
        let count = DropStore.allDrops.reduce(0) {
            $0 + ($1.isRecentlyAdded ? 1 : 0)
        }
        let recentlyAddedIndex = labelToggles.firstIndex(where: { $0.function == .recentlyAddedItems })
        if count == 0 {
            if let index = recentlyAddedIndex {
                labelToggles.remove(at: index)
                return true
            }
        } else {
            let t = newOrExistingToggle(of: .recentlyAddedItems, in: labelToggles, newCount: count)
            if let index = recentlyAddedIndex {
                labelToggles[index] = t
            } else if let index = labelToggles.firstIndex(where: { $0.function == .unlabeledItems }) {
                labelToggles.insert(t, at: index + 1)
                return true
            } else {
                labelToggles.append(t)
                return true
            }
        }
        return false
    }

    public func rebuildLabels() {
        var counts = [String: Int]()
        counts.reserveCapacity(labelToggles.count)
        var noLabelCount = 0
        var recentlyAddedCount = 0
        for item in DropStore.allDrops {
            item.labels.forEach {
                if let c = counts[$0] {
                    counts[$0] = c + 1
                } else {
                    counts[$0] = 1
                }
            }
            if item.labels.isEmpty {
                noLabelCount += 1
            }
            if item.isRecentlyAdded {
                recentlyAddedCount += 1
            }
        }

        let previousList = labelToggles
        labelToggles = counts.map { labelText, count in
            let function = Toggle.Function.userLabel(labelText)
            if let previousItem = previousList.first(where: { $0.function == function }) {
                let previousEnabled = previousItem.active
                let previousDisplayMode = previousItem.currentDisplayMode
                let previousPreferredMode = previousItem.preferredDisplayMode
                return Toggle(function: function, count: count, active: previousEnabled, currentDisplayMode: previousDisplayMode, preferredDisplayMode: previousPreferredMode)
            } else {
                return Toggle(function: function, count: count, active: false, currentDisplayMode: .collapsed, preferredDisplayMode: .scrolling)
            }
        }
        .sorted { $0.function.displayText.localizedCaseInsensitiveCompare($1.function.displayText) == .orderedAscending }

        if recentlyAddedCount > 0 {
            let t = newOrExistingToggle(of: .recentlyAddedItems, in: previousList, newCount: recentlyAddedCount)
            labelToggles.append(t)
        }

        if noLabelCount > 0 {
            let t = newOrExistingToggle(of: .unlabeledItems, in: previousList, newCount: noLabelCount)
            labelToggles.append(t)
        }
    }

    private func newOrExistingToggle(of function: Toggle.Function, in list: [Toggle], newCount: Int) -> Toggle {
        if let previousItem = list.first(where: { $0.function == function }) {
            let previousEnabled = previousItem.active
            let previousDisplayMode = previousItem.currentDisplayMode
            let previousPreferredMode = previousItem.preferredDisplayMode
            return Toggle(function: function, count: newCount, active: previousEnabled, currentDisplayMode: previousDisplayMode, preferredDisplayMode: previousPreferredMode)
        } else {
            let mode: DisplayMode = function == .recentlyAddedItems ? .scrolling : .collapsed
            return Toggle(function: function, count: newCount, active: false, currentDisplayMode: mode, preferredDisplayMode: .scrolling)
        }
    }

    public func updateLabel(_ label: Toggle) {
        if let i = labelToggles.firstIndex(where: { $0.function == label.function }) {
            labelToggles[i] = label
        }
    }

    public func renameLabel(_ oldName: String, to newName: String) {
        let wasEnabled = labelToggles.first { $0.function == .userLabel(oldName) }?.active ?? false

        DropStore.allDrops.forEach { i in
            if let oldIndex = i.labels.firstIndex(of: oldName) {
                if i.labels.contains(newName) {
                    i.labels.remove(at: oldIndex)
                } else {
                    i.labels[oldIndex] = newName
                }
                i.needsCloudPush = true
                i.flags.insert(.needsSaving)
            }
        }

        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels

        if wasEnabled, let i = labelToggles.firstIndex(where: { $0.function == .userLabel(newName) }) {
            var l = labelToggles[i]
            l.active = true
            labelToggles[i] = l
        }

        sendNotification(name: .LabelSelectionChanged, object: nil)
        Task {
            await Model.save()
        }
    }

    public func removeLabel(_ label: String) {
        for i in DropStore.allDrops where i.labels.contains(label) {
            i.labels.removeAll { $0 == label }
            i.needsCloudPush = true
            i.flags.insert(.needsSaving)
        }

        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels
        sendNotification(name: .LabelSelectionChanged, object: nil)
        Task {
            await Model.save()
        }
    }
}
