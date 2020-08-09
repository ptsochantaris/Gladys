//
//  Component+Copy.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Component {

	static var droppedIds = Set<UUID>()

	func register(with provider: NSItemProvider) {
		let t = typeIdentifier
		provider.registerDataRepresentation(forTypeIdentifier: t, visibility: .all) { completion -> Progress? in
			let p = Progress(totalUnitCount: 1)
			DispatchQueue.global(qos: .userInitiated).async {
				log("Responding with data block for type: \(t)")
                let response = self.dataForDroppingThread ?? self.bytes
				DispatchQueue.main.async {
					Component.droppedIds.insert(self.parentUuid)
                    p.completedUnitCount = 1
				}
				completion(response, nil)
			}
			return p
		}
	}
}
