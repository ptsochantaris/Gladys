import UIKit

extension Model {
    enum PasteResult {
        case success([ArchivedItem]), noData
    }

    @discardableResult
    static func pasteItems(from providers: [NSItemProvider], overrides: ImportOverrides?) -> PasteResult {
        if providers.isEmpty {
            return .noData
        }

        let currentFilter = currentWindow?.associatedFilter

        var items = [ArchivedItem]()
        var addedStuff = false
        for provider in providers { // separate item for each provider in the pasteboard
            for item in ArchivedItem.importData(providers: [provider], overrides: overrides) {
                if let currentFilter, currentFilter.isFilteringLabels, !PersistedOptions.dontAutoLabelNewItems {
                    item.labels = currentFilter.enabledLabelsForItems
                }
                Model.insert(drop: item, at: 0)
                items.append(item)
                addedStuff = true
            }
        }

        if addedStuff {
            _ = currentFilter?.update(signalUpdate: .animated)
        }

        return .success(items)
    }
}
