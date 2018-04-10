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
	static func setupCallbackSupport() {
		let m = Manager.shared
		m.callbackURLScheme = Manager.urlSchemes?.first
		m["paste-clipboard"] = { parameters, success, failure, cancel in
			if handlePasteRequest(title: parameters["title"], note: parameters["note"], labels: parameters["labels"], skipVisibleErrors: true) {
				success(nil)
			} else {
				failure(NSError.error(code: 1, failureReason: "Could not paste from clipboard"))
			}
		}
	}

	@discardableResult
	static func handlePasteRequest(title: String?, note: String?, labels: String?, skipVisibleErrors: Bool) -> Bool {
		ViewController.shared.dismissAnyPopOver()
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
		return ViewController.shared.pasteClipboard(overrides: importOverrides, skipVisibleErrors: skipVisibleErrors)
	}

	static func handlePossibleCallbackURL(url: URL) -> Bool {
		return Manager.shared.handleOpen(url: url)
	}
}
