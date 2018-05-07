//
//  ArchivedDropItemType+Copy.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension ArchivedDropItemType {

	static var droppedIds: Set<UUID>?

	func register(with provider: NSItemProvider) {
		provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
			let p = Progress(totalUnitCount: 1)
			p.completedUnitCount = 1
			DispatchQueue.global(qos: .userInitiated).async {
				log("Responding with data block")
				DispatchQueue.main.async {
					ArchivedDropItemType.droppedIds?.insert(self.parentUuid)
				}
				completion(self.dataForWrappedItem ?? self.bytes, nil)
			}
			return p
		}
	}

}
