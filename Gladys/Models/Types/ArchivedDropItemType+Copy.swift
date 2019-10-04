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
		let t = typeIdentifier
		provider.registerDataRepresentation(forTypeIdentifier: t, visibility: .all) { completion -> Progress? in
			let p = Progress(totalUnitCount: 1)
			DispatchQueue.global(qos: .userInitiated).async {
				log("Responding with data block for type: \(t)")
				DispatchQueue.main.async {
					ArchivedDropItemType.droppedIds?.insert(self.parentUuid)
				}
                let response = self.dataForDropping ?? self.bytes
                p.completedUnitCount = 1
				completion(response, nil)
			}
			return p
		}
	}
}
