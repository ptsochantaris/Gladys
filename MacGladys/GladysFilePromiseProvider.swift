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

		filename = dropItemType.prepareFilename(name: title.macFilenameSafe, directory: nil)

		if dropItemType.isWebURL, let s = dropItemType.encodedUrl {
			bytes = s.urlFileContent ?? Data()
		} else {
			bytes = dropItemType.dataForWrappedItem ?? dropItemType.bytes ?? Data()
		}
		super.init()
		fileType = dropItemType.typeIdentifier
		delegate = self
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
