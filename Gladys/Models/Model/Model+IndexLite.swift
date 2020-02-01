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
    static func reIndex(items: [CSSearchableItem], in index: CSSearchableIndex, completion: (() -> Void)? = nil) {
        index.indexSearchableItems(items) { error in
            if let error = error {
                log("Error indexing items: \(error.finalDescription)")
            } else {
                log("\(items.count) item(s) indexed")
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
}
