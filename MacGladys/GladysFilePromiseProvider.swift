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

		var titleMinusExtension = title
		if let ext = dropItemType.fileExtension {
			if ext == "jpeg", title.hasSuffix(".jpg") {
				titleMinusExtension = String(titleMinusExtension.dropLast(4))
			} else if titleMinusExtension.hasSuffix("." + ext) {
				titleMinusExtension = String(titleMinusExtension.dropLast(ext.count + 1))
			}
		}
		filename = dropItemType.prepareFilename(name: titleMinusExtension.macFilenameSafe, directory: nil)

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
