//
//  ArchivedDropItem+Share.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation
import MobileCoreServices

extension ArchivedDropItem {

	var attachmentForMessage: URL? {
		for t in typeItems {
			if t.typeConforms(to: kUTTypeContent) {
				return t.bytesPath
			}
		}
		return nil
	}

	var textForMessage: (String, URL?) {
		var webURL: URL?
		for t in typeItems {
			if let u = t.encodedUrl, !u.isFileURL {
				webURL = u as URL
				break
			}
		}
		if let webURL = webURL {
			let a = webURL.absoluteString
			if oneTitle != a {
				return (oneTitle, webURL)
			}
		}
		return (oneTitle, nil)
	}

}
