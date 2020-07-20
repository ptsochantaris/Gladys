//
//  IntentHandler.swift
//  GladysIntents
//
//  Created by Paul Tsochantaris on 30/09/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Intents
import UIKit

final class IntentHandler: INExtension, PasteClipboardIntentHandling, CopyItemIntentHandling, CopyComponentIntentHandling {

	private var newItems = [ArchivedItem]()
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
        completion(CopyItemIntentResponse(code: .ready, userActivity: nil))
	}

	func confirm(intent: CopyComponentIntent, completion: @escaping (CopyComponentIntentResponse) -> Void) {
        completion(CopyComponentIntentResponse(code: .ready, userActivity: nil))
	}

	func confirm(intent: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
		itemProviders = UIPasteboard.general.itemProviders
		let loadCount = itemProviders.count

		if loadCount == 0 {
			completion(PasteClipboardIntentResponse(code: .noData, userActivity: nil))
			return
		}

		newItems.removeAll()
		intentCompletion = nil

		completion(PasteClipboardIntentResponse(code: .ready, userActivity: nil))
	}

	func handle(intent: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
		intentCompletion = completion
        
        let n = NotificationCenter.default
        n.removeObserver(self)
        n.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)

        for provider in itemProviders {
			for newItem in ArchivedItem.importData(providers: [provider], overrides: nil) {
				newItems.append(newItem)
			}
		}
	}

    @objc private func itemIngested(_ notification: Notification) {
        if !Model.doneIngesting {
            return
        }
        Model.insertNewItemsWithoutLoading(items: newItems.reversed(), addToDrops: false)
        intentCompletion?(PasteClipboardIntentResponse(code: .success, userActivity: nil))
        intentCompletion = nil
        newItems.removeAll()
        itemProviders.removeAll()
        
        NotificationCenter.default.removeObserver(self)
        CloudManager.signalExtensionUpdate()
	}
}
