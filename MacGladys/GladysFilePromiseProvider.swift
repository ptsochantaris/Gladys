//
//  GladysFilePromiseProvider.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 06/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa

class GladysFilePromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {

	let bytes: Data
	let filename: String

	init(dropItemType: ArchivedDropItemType, title: String) {

		filename = dropItemType.prepareFilename(name: title.filenameSafe, directory: nil)

		if dropItemType.typeIdentifier == "public.url", let s = dropItemType.encodedUrl?.absoluteString {
			bytes = "[InternetShortcut]\r\nURL=\(s)\r\n".data(using: .utf8)!
		} else {
			bytes = dropItemType.dataForWrappedItem ?? dropItemType.bytes ?? Data()
		}
		super.init()
		self.fileType = dropItemType.typeIdentifier
		self.delegate = self
	}

	func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				try self.bytes.write(to: url)
				completionHandler(nil)
			} catch {
				completionHandler(error)
			}
		}
	}

	func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
		return filename
	}
}
