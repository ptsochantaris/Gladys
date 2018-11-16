//
//  GladysFilePromiseProvider.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 06/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa

final class GladysFilePromiseProvider : NSFilePromiseProvider {

	static func provider(for component: ArchivedDropItemType, with title: String, extraItems: [ArchivedDropItemType]) -> GladysFilePromiseProvider {
		let title = component.prepareFilename(name: title.dropFilenameSafe, directory: nil)
		let delegate = GladysFileProviderDelegate(item: component, title: title)
		let p = GladysFilePromiseProvider(fileType: "public.data", delegate: delegate)
		p.strongDelegate = delegate
		p.extraItems = extraItems
		return p
	}

	private var extraItems: [ArchivedDropItemType]?
	private var strongDelegate: GladysFileProviderDelegate?

	public override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
		let types = super.writableTypes(for: pasteboard)
		let newItems = (extraItems ?? []).map { NSPasteboard.PasteboardType($0.typeIdentifier) }
		return newItems + types
	}

	public override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
		if type.rawValue == "public.data" {
			return super.writingOptions(forType: type, pasteboard: pasteboard)
		}
		return []
	}

	public override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
		switch type.rawValue {
		case "public.data", "com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.promised-file-name", "com.apple.pasteboard.promised-file-content-type", "com.apple.pasteboard.NSFilePromiseID":
			return super.pasteboardPropertyList(forType: type)
		default:
			let item = extraItems?.first { $0.typeIdentifier == type.rawValue }
			return item?.bytes
		}
	}
}

final class GladysFileProviderDelegate: NSObject, NSFilePromiseProviderDelegate {

	private weak var typeItem: ArchivedDropItemType?
	private let title: String

	init(item: ArchivedDropItemType, title: String) {
		typeItem = item
		self.title = title
		super.init()
	}

	func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
		return title
	}

	func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
		let bytes: Data
		if typeItem?.isWebURL == true, let s = typeItem?.encodedUrl {
			bytes = s.urlFileContent ?? Data()
		} else {
			bytes = typeItem?.dataForWrappedItem ?? typeItem?.bytes ?? Data()
		}
		do {
			try bytes.write(to: url)
			completionHandler(nil)
		}
		catch {
			completionHandler(error)
		}
	}
}
