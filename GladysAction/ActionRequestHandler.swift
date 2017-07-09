//
//  ActionRequestHandler.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class ActionRequestHandler: NSObject, NSExtensionRequestHandling, LoadCompletionDelegate {

	private var loadCount = 0
	private var context: NSExtensionContext?
	private let model = Model()

    func beginRequest(with context: NSExtensionContext) {
		self.context = context

		for inputItem in context.inputItems as? [NSExtensionItem] ?? [] {
			loadCount += inputItem.attachments?.count ?? 0
		}

		if loadCount == 0 {
			context.completeRequest(returningItems: nil, completionHandler: nil)
			return
		}

		let newTotal = model.drops.count + loadCount
		if !model.infiniteMode && newTotal > model.nonInfiniteItemLimit {
			let message = "This operation would result in a total of \(newTotal) items, and Gladys holds up to \(model.nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase."
			let error = NSError(domain: "build.bru.Gladys.error", code: 84, userInfo: [ NSLocalizedDescriptionKey: message ])
			context.cancelRequest(withError: error)
			return
		}

		for inputItem in context.inputItems as? [NSExtensionItem] ?? [] {
			for provider in inputItem.attachments as? [NSItemProvider] ?? [] {
				let newItem = ArchivedDropItem(provider: provider, delegate: self)
				model.drops.insert(newItem, at: 0)
			}
		}

    }

	func loadCompleted(sender: AnyObject, success: Bool) {
		loadCount -= 1
		if loadCount == 0 {
			model.needsSave = true
			context?.completeRequest(returningItems: nil, completionHandler: nil)
			context = nil
		}
	}

	func loadingProgress(sender: AnyObject) {}
}

