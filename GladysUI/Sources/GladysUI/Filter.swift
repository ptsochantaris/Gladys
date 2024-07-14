import CoreSpotlight
import Foundation
#if canImport(UIKit)
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

@MainActor
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
                "square.grid.3x3"
            case .byLabel:
                "square.grid.3x1.below.line.grid.1x2"
            }
        }
    }

    public weak var delegate: FilterDelegate?

    public var groupingMode = GroupingMode.flat
    public var isFilteringText = false
    public var filteredDrops: ContiguousArray<ArchivedItem>

    private var modelFilter: String?
    private let manualDropSource: ContiguousArray<ArchivedItem>?

    private var dropSource: ContiguousArray<ArchivedItem> {
        manualDropSource ?? DropStore.allDrops
    }

    public init(manualDropSource: ContiguousArray<ArchivedItem>? = nil) {
        self.manualDropSource = manualDropSource
        filteredDrops = manualDropSource ?? DropStore.allDrops
        rebuildLabels()
    }

    public func sizeOfVisibleItemsInBytes() async -> Int64 {
        await Task.detached { [filteredDrops] in
            var total: Int64 = 0
            for drop in filteredDrops {
                total += await drop.sizeInBytes
            }
            return total
        }.value
    }

    public var isFilteringLabels: Bool {
        labelToggles.contains { $0.active }
    }

    public var isFiltering: Bool {
        isFilteringText || isFilteringLabels
    }

    public var text: String? {
        get {
            modelFilter
        }
        set {
            let v = newValue == "" ? nil : newValue
            if modelFilter != v {
                modelFilter = v
                update(signalUpdate: .animated)
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
        var count = 0
        for drop in filteredDrops {
            switch toggle.function {
            case let .userLabel(text):
                if drop.labels.contains(text) {
                    count += 1
                }
            case .unlabeledItems:
                if drop.labels.isEmpty {
                    count += 1
                }
            case .recentlyAddedItems:
                if drop.isRecentlyAdded {
                    count += 1
                }
            }
        }
        return count
    }

    private func findIds(for queryString: String) -> Set<UUID> {
        var replacementResults = Set<UUID>()

        let q = CSSearchQuery(queryString: queryString, queryContext: nil)
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
                log("Search error: \(error.localizedDescription)")
            }
            lock.unlock()
        }
        q.start()
        if !lock.lock(before: Date(timeIntervalSinceNow: 10)) {
            q.cancel()
        }
        lock.unlock()
        return replacementResults
    }

    private func checkForChange(between a: ContiguousArray<ArchivedItem>, and b: ContiguousArray<ArchivedItem>) -> Bool {
        let ac = a.count
        if ac != b.count {
            return true
        }

        for i in 0 ..< ac where a[i].uuid != b[i].uuid {
            return true
        }

        return false
    }

    public func update(signalUpdate: UpdateType, forceAnnounce: Bool = false) {
        // label pass

        let allDrops = dropSource

        let enabledToggles = labelToggles.filter(\.active)
        let postLabelDrops: ContiguousArray<ArchivedItem>
        if enabledToggles.isEmpty {
            postLabelDrops = allDrops

        } else if PersistedOptions.exclusiveMultipleLabels {
            let expectedCount = enabledToggles.count
            postLabelDrops = allDrops.filter { item in
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
            postLabelDrops = allDrops.filter { item in
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

        let previousFilteredDrops = filteredDrops
        // text pass

        if let terms = Filter.terms(for: modelFilter), terms.isPopulated {
            let queryString: String = if terms.count > 1 {
                if PersistedOptions.inclusiveSearchTerms {
                    "(" + terms.joined(separator: ") || (") + ")"
                } else {
                    "(" + terms.joined(separator: ") && (") + ")"
                }
            } else {
                terms.first ?? ""
            }

            isFilteringText = true
            let ids = findIds(for: queryString)
            filteredDrops = postLabelDrops.filter { ids.contains($0.uuid) }
        } else {
            isFilteringText = false
            filteredDrops = postLabelDrops
        }

        if forceAnnounce || checkForChange(between: previousFilteredDrops, and: filteredDrops) {
            Model.updateBadge()
            if signalUpdate != .none {
                delegate?.modelFilterContextChanged(self, animate: signalUpdate == .animated)

                #if canImport(UIKit)
                    if isFilteringText, UIAccessibility.isVoiceOverRunning {
                        let resultString: String
                        let c = filteredDrops.count
                        if c == 0 {
                            resultString = "No results"
                        } else if c == 1 {
                            resultString = "One result"
                        } else {
                            resultString = "\(c) results"
                        }
                        UIAccessibility.post(notification: .announcement, argument: resultString)
                    }
                #endif
            }
        }
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
        let items = PersistedOptions.exportOnlyVisibleItems ? filteredDrops : dropSource // copy
        return items.filter(\.goodToSave)
    }

    public var labelToggles = [Toggle]()

    public func applyLabelConfig(from newToggles: [Toggle]) {
        labelToggles = labelToggles.map { existingToggle in
            if let newToggle = newToggles.first(where: { $0.function == existingToggle.function }) {
                Toggle(function: newToggle.function, count: existingToggle.count, active: newToggle.active, currentDisplayMode: newToggle.currentDisplayMode, preferredDisplayMode: newToggle.preferredDisplayMode)
            } else {
                existingToggle
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
                    labels
                }
            }

            public var title: String {
                switch self {
                case let .filtered(_, title), let .recent(_, title):
                    title
                }
            }
        }

        public enum Function: Hashable, Codable {
            case userLabel(String)
            case recentlyAddedItems
            case unlabeledItems

            public var displayText: String {
                switch self {
                case let .userLabel(name): name
                case .unlabeledItems: "Items with no labels"
                case .recentlyAddedItems: "Recently added"
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
                case .none: nil
                case .some: "Applied to some selected items"
                case .all: "Applied to all selected items"
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
        var res: [Filter.Toggle] = if isFilteringLabels {
            labelToggles.filter(\.active)
        } else {
            labelToggles
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
        let count = dropSource.reduce(0) {
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
        for item in dropSource {
            for label in item.labels {
                if let c = counts[label] {
                    counts[label] = c + 1
                } else {
                    counts[label] = 1
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

        for i in dropSource {
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

        sendNotification(name: .LabelSelectionChanged)
        Task {
            await Model.save()
        }
    }

    public func removeLabel(_ label: String) {
        for i in dropSource where i.labels.contains(label) {
            i.labels.removeAll { $0 == label }
            i.needsCloudPush = true
            i.flags.insert(.needsSaving)
        }

        rebuildLabels() // needed because of UI updates that can occur before the save which rebuilds the labels
        sendNotification(name: .LabelSelectionChanged)
        Task {
            await Model.save()
        }
    }
}
