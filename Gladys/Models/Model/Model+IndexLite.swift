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
	static func reIndexWithoutLoading(items: [ArchivedDropItem], in index: CSSearchableIndex = CSSearchableIndex.default(), completion: (()->Void)? = nil) {
		let searchableItems = items.map { $0.searchableItem }
		let count = items.count
		index.indexSearchableItems(searchableItems) { error in
			if let error = error {
				log("Error indexing items: \(error.finalDescription)")
			} else {
				log("\(count) item(s) indexed")
			}
			completion?()
		}
	}
}
