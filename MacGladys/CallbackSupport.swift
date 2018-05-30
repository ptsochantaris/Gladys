//
//  CallbackSupport.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 30/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CallbackURLKit

struct CallbackSupport {
	private static func handle(result: Bool, success: @escaping SuccessCallback, failure: @escaping FailureCallback) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			if result {
				success(nil)
			} else {
				failure(NSError.error(code: 1, failureReason: "Items could not be added."))
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
			} else {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					failure(NSError.error(code: 3, failureReason: "'text' or 'url' parameter required."))
				}
			}
		}

		m["paste-share-pasteboard"] = { parameters, success, failure, cancel in
			let pasteboard = NSPasteboard(name: sharingPasteboard)
			ViewController.shared.addItems(from: pasteboard, at: IndexPath(item: 0, section: 0), overrides: nil)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				ViewController.shared.reloadData()
				DistributedNotificationCenter.default().post(name: .SharingPasteboardPasted, object: "build.bru.MacGladys")
			}
		}
	}

	static private func createOverrides(from parameters: [String : String]) -> ImportOverrides {
		let title = parameters["title"]
		let labels = parameters["labels"]
		let note = parameters["note"]
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		return ImportOverrides(title: title, note: note, labels: labelsList)
	}

	@discardableResult
	static func handlePasteRequest(title: String?, note: String?, labels: String?) -> Bool {
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
		return ViewController.shared.addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: importOverrides)
	}

	@discardableResult
	static func handleCreateRequest(object: NSItemProviderWriting, overrides: ImportOverrides) -> Bool {
		let p = NSItemProvider(object: object)
		return ViewController.shared.addItems(itemProviders: [p], name: object.description, indexPath: IndexPath(item: 0, section: 0), overrides: overrides)
	}

	@discardableResult
	static func handlePossibleCallbackURL(url: URL) -> Bool {
		return Manager.shared.handleOpen(url: url)
	}
}
