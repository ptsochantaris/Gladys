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
	static func setupCallbackSupport() {
		let m = Manager.shared
		m.callbackURLScheme = Manager.urlSchemes?.first
		m["paste-clipboard"] = { parameters, success, failure, cancel in
			let result = handlePasteRequest(title: parameters["title"], note: parameters["note"], labels: parameters["labels"], skipVisibleErrors: true)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				if result {
					success(nil)
				} else {
					failure(NSError.error(code: 1, failureReason: "Items could not be added."))
				}
			}
		}
	}

	@discardableResult
	static func handlePasteRequest(title: String?, note: String?, labels: String?, skipVisibleErrors: Bool) -> Bool {
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
		return ViewController.shared.addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: importOverrides)
	}

	@discardableResult
	static func handlePossibleCallbackURL(url: URL) -> Bool {
		return Manager.shared.handleOpen(url: url)
	}
}
