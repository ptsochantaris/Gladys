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
	private var newItems = [ArchivedDropItem]()
	private var itemProviders = [NSItemProvider]()
	private var intentCompletion: ((PasteClipboardIntentResponse) -> Void)?

	func handle(intent: CopyComponentIntent, completion: @escaping (CopyComponentIntentResponse) -> Void) {
		guard let uuidString = intent.component?.identifier else {
			completion(CopyComponentIntentResponse(code: .failure, userActivity: nil))
			return
		}

		guard let (_, component) = Model.locateComponentWithoutLoading(uuid: uuidString) else {
			completion(CopyComponentIntentResponse(code: .failure, userActivity: nil))
			return
		}

		component.copyToPasteboard(donateShortcut: false)
		completion(CopyComponentIntentResponse(code: .success, userActivity: nil))
	}

	/////////////////////////////

	func handle(intent: CopyItemIntent, completion: @escaping (CopyItemIntentResponse) -> Void) {
		guard let uuidString = intent.item?.identifier, let uuid = UUID(uuidString: uuidString) else {
			completion(CopyItemIntentResponse(code: .failure, userActivity: nil))
			return
		}

		guard let item = Model.locateItemWithoutLoading(uuid: uuid.uuidString) else {
			completion(CopyItemIntentResponse(code: .failure, userActivity: nil))
			return
		}

		item.copyToPasteboard(donateShortcut: false)
		completion(CopyItemIntentResponse(code: .success, userActivity: nil))
	}

	/////////////////////////////

	func confirm(intent: CopyItemIntent, completion: @escaping (CopyItemIntentResponse) -> Void) {
		if Model.legacyModeCheckWithoutLoading() {
			completion(CopyItemIntentResponse(code: .legacyMode, userActivity: nil))
		} else {
			completion(CopyItemIntentResponse(code: .ready, userActivity: nil))
		}
	}

	func confirm(intent: CopyComponentIntent, completion: @escaping (CopyComponentIntentResponse) -> Void) {
		if Model.legacyModeCheckWithoutLoading() {
			completion(CopyComponentIntentResponse(code: .legacyMode, userActivity: nil))
		} else {
			completion(CopyComponentIntentResponse(code: .ready, userActivity: nil))
		}
	}

	func confirm(intent: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
		itemProviders = UIPasteboard.general.itemProviders
		loadCount = itemProviders.count

		if loadCount == 0 {
			completion(PasteClipboardIntentResponse(code: .noData, userActivity: nil))
			return
		}

		newItems.removeAll()
		intentCompletion = nil

		if Model.legacyModeCheckWithoutLoading() {
			completion(PasteClipboardIntentResponse(code: .legacyMode, userActivity: nil))
			return
		}

		let newTotal = Model.countSavedItemsWithoutLoading() + loadCount
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
			newItems.append(newItem)
		}
	}

	func itemIngested(item: ArchivedDropItem) {
		loadCount -= 1
		if loadCount == 0 {
			pasteCommit()
		}
	}

	private func pasteCommit() {
		Model.insertNewItemsWithoutLoading(items: newItems)
		Model.reIndexWithoutLoading(items: newItems) {
			DispatchQueue.main.async { [weak self] in
				self?.pasteDone()
			}
		}
	}

	private func pasteDone() {
		intentCompletion?(PasteClipboardIntentResponse(code: .success, userActivity: nil))
		intentCompletion = nil
		newItems.removeAll()
		itemProviders.removeAll()
		loadCount = 0
	}
}
