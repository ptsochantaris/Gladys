//
//  GladysFilePromiseProvider.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 06/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa

final class GladysFilePromiseProvider: NSObject, NSPasteboardItemDataProvider {

	func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
		if let pasteboard = pasteboard {

			var location: CFURL?
			var pboardRef: Pasteboard?
			PasteboardCreate(pasteboard.name as CFString, &pboardRef)
			if let pboardRef = pboardRef {
				PasteboardSynchronize(pboardRef)
				PasteboardCopyPasteLocation(pboardRef, &location)
			}

			if var location = (location as URL?), let parent = Model.item(uuid: dropItemType.parentUuid) {
				let name = dropItemType.prepareFilename(name: parent.displayTitleOrUuid.macFilenameSafe, directory: nil)
				location.appendPathComponent(name)
				if dropItemType.isWebURL, let s = dropItemType.encodedUrl {
					let bytes = s.urlFileContent ?? Data()
					try? bytes.write(to: location)
				} else {
					let bytes = dropItemType.dataForWrappedItem ?? dropItemType.bytes ?? Data()
					try? bytes.write(to: location)
				}
			}
		}
	}

	private let dropItemType: ArchivedDropItemType

	init(dropItemType: ArchivedDropItemType) {
		self.dropItemType = dropItemType
		super.init()
	}
}
