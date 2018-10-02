//
//  ArchivedDropItem+Copy.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
#if MAINAPP
import Intents
#endif

extension ArchivedDropItem {
	private var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = displayText.0
		typeItems.forEach { $0.register(with: p) }
		return p
	}

	#if MAINAPP || TODAYEXTENSION
	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}
	#endif

	func copyToPasteboard() {
		UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
		donateCopyIntent()
	}

	private func donateCopyIntent() {
		#if MAINAPP
		if #available(iOS 12.0, *) {
			let intent = CopyItemIntent()
			let trimmedName = displayTitleOrUuid.truncateWithEllipses(limit: 24)
			intent.suggestedInvocationPhrase = "Copy '\(trimmedName)' from Gladys"
			intent.item = INObject(identifier: uuid.uuidString, display: trimmedName)
			let interaction = INInteraction(intent: intent, response: nil)
			interaction.identifier = "copy-\(uuid.uuidString)"
			interaction.donate { error in
				if let error = error {
					log("Error donating copy shortcut: \(error.localizedDescription)")
				} else {
					log("Donated copy shortcut")
				}
			}
		}
		#endif
	}

	func removeIntents() {
		#if MAINAPP
		if #available(iOS 12.0, *) {
			INInteraction.delete(with: ["copy-\(uuid.uuidString)"]) { error in
				if let error = error {
					log("Copy intent could not be removed: \(error.localizedDescription)")
				} else {
					log("Copy intent removed")
				}
			}
			for item in typeItems {
				item.removeIntents()
			}
		}
		#endif
	}
}
