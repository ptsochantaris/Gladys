//
//  ArchivedDropItemType+Intents.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 02/10/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import Intents

extension ArchivedDropItemType {
	func copyToPasteboard() {
		UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
		donateCopyIntent()
	}

	var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = oneTitle
		register(with: p)
		return p
	}

	private func donateCopyIntent() {
		if #available(iOS 12.0, *) {
			let intent = CopyComponentIntent()
			let trimmedName = oneTitle.truncateWithEllipses(limit: 24)
			intent.suggestedInvocationPhrase = "Copy '\(trimmedName)' from Gladys"
			intent.component = INObject(identifier: uuid.uuidString, display: trimmedName)
			let interaction = INInteraction(intent: intent, response: nil)
			interaction.identifier = "copy-\(uuid.uuidString)"
			interaction.donate { error in
				if let error = error {
					log("Error donating component copy shortcut: \(error.localizedDescription)")
				} else {
					log("Donated copy shortcut")
				}
			}
		}
	}

	func removeIntents() {
		if #available(iOS 12.0, *) {
			INInteraction.delete(with: ["copy-\(uuid.uuidString)"]) { error in
				if let error = error {
					log("Copy intent for component could not be removed: \(error.localizedDescription)")
				} else {
					log("Copy intent for component removed")
				}
			}
		}
	}
}
