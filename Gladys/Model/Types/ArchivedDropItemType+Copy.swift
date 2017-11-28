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

	var dataForWrappedItem: Data? {
		if classWasWrapped && typeIdentifier.hasPrefix("public.") {
			let decoded = decode()
			if let s = decoded as? String {
				return s.data(using: .utf8)
			} else if let s = decoded as? NSAttributedString {
				return try? s.data(from: NSMakeRange(0, s.string.count), documentAttributes: [:])
			} else if let s = decoded as? NSURL {
				return s.absoluteString?.data(using: .utf8)
			}
		}
		return nil
	}
}
