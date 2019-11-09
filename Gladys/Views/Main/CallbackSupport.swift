//
//  CallbackSupport.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CallbackURLKit
import MobileCoreServices

struct CallbackSupport {
    private static func handle(result: Model.PasteResult, success: @escaping SuccessCallback, failure: @escaping FailureCallback) {
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
			let result = handlePasteRequest(title: parameters["title"], note: parameters["note"], labels: parameters["labels"])
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

			} else if let text = parameters["base64data"] as String? {
				if let data = Data(base64Encoded: text) {
					let result = handleEncodedRequest(data, overrides: importOverrides)
					handle(result: result, success: success, failure: failure)

				} else {
					failure(NSError.error(code: 5, failureReason: "Could not decode base64 data string."))
				}

			} else {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					failure(NSError.error(code: 3, failureReason: "One of 'text', 'url', or 'base64data' parameters is required."))
				}
			}
		}
	}

	@discardableResult
	static func handleEncodedRequest(_ data: Data, overrides: ImportOverrides) -> Model.PasteResult {
		let p = NSItemProvider()
		p.suggestedName = overrides.title
		p.registerDataRepresentation(forTypeIdentifier: kUTTypeData as String, visibility: .all) { completion -> Progress? in
			completion(data, nil)
			return nil
		}
		return Model.pasteItems(from: [p], overrides: overrides)
	}

	@discardableResult
	static func handlePasteRequest(title: String?, note: String?, labels: String?) -> Model.PasteResult {
		ViewController.shared.dismissAnyPopOver()
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
        defer {
            Model.donatePasteIntent()
        }
		return Model.pasteItems(from: UIPasteboard.general.itemProviders, overrides: importOverrides)
	}

	@discardableResult
	private static func handleCreateRequest(object: NSItemProviderWriting, overrides: ImportOverrides) -> Model.PasteResult {
		return Model.pasteItems(from: [NSItemProvider(object: object)], overrides: overrides)
	}
}
