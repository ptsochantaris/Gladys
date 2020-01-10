//
//  Model+Importing.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension Model {
    enum PasteResult {
        case success, noData, tooManyItems
    }

    @discardableResult
    static func pasteItems(from providers: [NSItemProvider], overrides: ImportOverrides?) -> PasteResult {
        
        if providers.count == 0 {
            return .noData
        }

        if IAPManager.shared.checkInfiniteMode(for: 1) {
            return .tooManyItems
        }
        
        let currentFilter = currentWindow?.associatedFilter

        var uuids = Set<UUID>()
        var addedStuff = false
        for provider in providers { // separate item for each provider in the pasteboard
            for item in ArchivedItem.importData(providers: [provider], overrides: overrides) {
                if let currentFilter = currentFilter, currentFilter.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
                    item.labels = currentFilter.enabledLabelsForItems
                }
                Model.drops.insert(item, at: 0)
                uuids.insert(item.uuid)
                addedStuff = true
            }
        }
        
        if addedStuff {
            Model.save()
        }
        
        return .success
    }
}
