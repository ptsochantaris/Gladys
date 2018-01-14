//
//  ArchivedDropItem+Copy.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension ArchivedDropItem {
	private var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = displayText.0
		typeItems.forEach { $0.register(with: p) }
		return p
	}

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

	func copyToPasteboard() {
		UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
	}
}
