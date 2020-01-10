//
//  ArchivedItem+Share.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation
import MobileCoreServices

extension ArchivedItem {

	var attachmentForMessage: URL? {
		for t in components {
			if t.typeConforms(to: kUTTypeContent) {
				return t.bytesPath
			}
		}
		return nil
	}

	var textForMessage: (String, URL?) {
		var webURL: URL?
		for t in components {
			if let u = t.encodedUrl, !u.isFileURL {
				webURL = u as URL
				break
			}
		}
		let tile = displayTitleOrUuid
		if let webURL = webURL {
			let a = webURL.absoluteString
			if tile != a {
				return (tile, webURL)
			}
		}
		return (tile, nil)
	}

	var attachableTypeItem: Component? {
		if let i = components.max(by: { $0.attachPriority < $1.attachPriority }), i.attachPriority > 0 {
			return i
		} else {
			return nil
		}
	}

}
