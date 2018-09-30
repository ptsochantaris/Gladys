//
//  CallbackSupport.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CallbackURLKit

struct CallbackSupport {
	private static func handle(result: PasteResult, success: @escaping SuccessCallback, failure: @escaping FailureCallback) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			switch result {
			case .success:
				success(nil)
			case .noData:
				failure(NSError.error(code: 1, failureReason: "Clipboard is empty."))
			case .tooManyItems:
				failure(NSError.error(code: 2, failureReason: "Gladys cannot hold more items."))
			}
		}
	}

	static func setupCallbackSupport() {
		let m = Manager.shared
		m.callbackURLScheme = Manager.urlSchemes?.first

		m["paste-clipboard"] = { parameters, success, failure, cancel in
			let result = handlePasteRequest(title: parameters["title"], note: parameters["note"], labels: parameters["labels"], skipVisibleErrors: true)
			handle(result: result, success: success, failure: failure)
		}

		m["create-item"] = { parameters, success, failure, cancel in
			let importOverrides = createOverrides(from: parameters)
			if let text = parameters["text"] as NSString? {
				let result = handleCreateRequest(object: text, overrides: importOverrides)
				handle(result: result, success: success, failure: failure)

			} else if let text = parameters["url"] {
				if let url = NSURL(string: text) {
					let result = handleCreateRequest(object: url, overrides: importOverrides)
					handle(result: result, success: success, failure: failure)

				} else {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						failure(NSError.error(code: 4, failureReason: "Invalid URL."))
					}
				}
			} else {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					failure(NSError.error(code: 3, failureReason: "'text' or 'url' parameter required."))
				}
			}
		}
	}
	
	@discardableResult
	static func handlePasteRequest(title: String?, note: String?, labels: String?, skipVisibleErrors: Bool) -> PasteResult {
		ViewController.shared.dismissAnyPopOver()
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
		return ViewController.shared.pasteItems(from: UIPasteboard.general.itemProviders, overrides: importOverrides, skipVisibleErrors: skipVisibleErrors)
	}

	@discardableResult
	static func handleCreateRequest(object: NSItemProviderWriting, overrides: ImportOverrides) -> PasteResult {
		return ViewController.shared.pasteItems(from: [NSItemProvider(object: object)], overrides: overrides, skipVisibleErrors: true)
	}
}
