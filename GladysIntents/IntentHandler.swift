//
//  IntentHandler.swift
//  GladysIntents
//
//  Created by Paul Tsochantaris on 30/09/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Intents
import CoreSpotlight
import UIKit

final class IntentHandler: INExtension, PasteClipboardIntentHandling, ItemIngestionDelegate {

	private var loadCount = 0
	private var newItemIds = [String]()
	private var intentCompletion: ((PasteClipboardIntentResponse) -> Void)?
	private var itemProviders = [NSItemProvider]()

	func confirm(intent: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
		itemProviders = UIPasteboard.general.itemProviders
		loadCount = itemProviders.count

		if loadCount == 0 {
			completion(PasteClipboardIntentResponse(code: .noData, userActivity: nil))
			return
		}

		newItemIds.removeAll()
		Model.reset()
		Model.reloadDataIfNeeded()

		if Model.legacyMode {
			completion(PasteClipboardIntentResponse(code: .legacyMode, userActivity: nil))
			return
		}

		let newTotal = Model.drops.count + loadCount
		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			// ensure the app wasn't just registered, just in case, before we warn the user
			reVerifyInfiniteMode()
		}

		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			completion(PasteClipboardIntentResponse(code: .tooManyItems, userActivity: nil))
			return
		}

		completion(PasteClipboardIntentResponse(code: .ready, userActivity: nil))
	}

	func handle(intent: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
		intentCompletion = completion

		for newItem in ArchivedDropItem.importData(providers: itemProviders, delegate: self, overrides: nil) {
			Model.drops.insert(newItem, at: 0)
			newItemIds.append(newItem.uuid.uuidString)
		}
	}

	func itemIngested(item: ArchivedDropItem) {
		loadCount -= 1
		if loadCount == 0 {
			Model.save()
			commit()
		}
	}

	private func commit() {
		Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: newItemIds) {
			DispatchQueue.main.async { [weak self] in
				self?.intentCompletion?(PasteClipboardIntentResponse(code: .success, userActivity: nil))
			}
		}
	}
}
