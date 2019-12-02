//
//  Model+IndexLite.swift
//  GladysIntents
//
//  Created by Paul Tsochantaris on 14/11/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CoreSpotlight

extension Model {
    static func reIndex(items: [ArchivedDropItem], in index: CSSearchableIndex, completion: (()->Void)? = nil) {
        let searchableItems = items.map { $0.searchableItem }
        index.indexSearchableItems(searchableItems) { error in
            if let error = error {
                log("Error indexing items: \(error.finalDescription)")
            } else {
                log("\(searchableItems.count) item(s) indexed")
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
}
