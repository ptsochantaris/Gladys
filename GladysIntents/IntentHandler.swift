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

final class IntentHandler: INExtension, PasteClipboardIntentHandling, ItemIngestionDelegate, CopyItemIntentHandling, CopyComponentIntentHandling {

	private var loadCount = 0
	private var newItemIds = [String]()
	private var intentCompletion: ((PasteClipboardIntentResponse) -> Void)?

	func handle(intent: CopyComponentIntent, completion: @escaping (CopyComponentIntentResponse) -> Void) {
		guard let uuidString = intent.component?.identifier else {
			completion(CopyComponentIntentResponse(code: .failure, userActivity: nil))
			return
		}

		Model.reset()
		Model.reloadDataIfNeeded()

		guard let item = Model.typeItem(uuid: uuidString) else {
			completion(CopyComponentIntentResponse(code: .failure, userActivity: nil))
			return
		}

		item.copyToPasteboard()
		completion(CopyComponentIntentResponse(code: .success, userActivity: nil))
	}

	/////////////////////////////

	func handle(intent: CopyItemIntent, completion: @escaping (CopyItemIntentResponse) -> Void) {
		guard let uuidString = intent.item?.identifier, let uuid = UUID(uuidString: uuidString) else {
			completion(CopyItemIntentResponse(code: .failure, userActivity: nil))
			return
		}

		Model.reset()
		Model.reloadDataIfNeeded()

		guard let item = Model.item(uuid: uuid) else {
			completion(CopyItemIntentResponse(code: .failure, userActivity: nil))
			return
		}

		item.copyToPasteboard()
		completion(CopyItemIntentResponse(code: .success, userActivity: nil))
	}

	/////////////////////////////

	func handle(intent: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
		let itemProviders = UIPasteboard.general.itemProviders
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
