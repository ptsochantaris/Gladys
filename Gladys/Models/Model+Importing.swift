//
//  Model+Importing.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import Foundation

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

        let filteredCount = Model.filteredDrops.count

        for provider in providers { // separate item for each provider in the pasteboard
            for item in ArchivedDropItem.importData(providers: [provider], overrides: overrides) {
                if Model.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
                    item.labels = Model.enabledLabelsForItems
                }
                Model.drops.insert(item, at: 0)
            }
        }
        
        Model.forceUpdateFilter(signalUpdate: false)
        let change = Model.filteredDrops.count - filteredCount
        if change > 0 {
            NotificationCenter.default.post(name: .ItemsCreated, object: change)
        }
        
        return .success
    }
}
