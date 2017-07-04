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
			for provider in inputItem.attachments as? [NSItemProvider] ?? [] {
				let newItem = ArchivedDropItem(provider: provider, delegate: self)
				model.drops.insert(newItem, at: 0)
			}
		}

		if loadCount == 0 {
			context.completeRequest(returningItems: nil, completionHandler: nil)
		}
    }

	func loadCompleted(sender: AnyObject, success: Bool) {
		loadCount -= 1
		if loadCount == 0 {
			context?.completeRequest(returningItems: nil, completionHandler: nil)
			context = nil
			model.save()
		}
	}

	func loadingProgress(sender: AnyObject) {}
}

