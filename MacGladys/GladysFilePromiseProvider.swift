//
//  GladysFilePromiseProvider.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 06/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class GladysFilePromiseProvider : NSFilePromiseProvider {

	static func provider(for component: ArchivedDropItemType, with title: String, extraItems: [ArchivedDropItemType], forDrag: Bool) -> GladysFilePromiseProvider {
		let title = component.prepareFilename(name: title.dropFilenameSafe, directory: nil)
		let tempPath = component.bytesPath.deletingLastPathComponent().appendingPathComponent(title)

		let delegate = GladysFileProviderDelegate(item: component, title: title, tempPath: tempPath)

		let p = GladysFilePromiseProvider(fileType: "public.data", delegate: delegate)
		if forDrag {
			p.component = component
			p.tempPath = tempPath
		}
		p.strongDelegate = delegate
		p.extraItems = extraItems
		return p
	}

	private var extraItems: [ArchivedDropItemType]?
	private var strongDelegate: GladysFileProviderDelegate?
	private var component: ArchivedDropItemType?
	private var tempPath: URL?

	public override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
		var types = super.writableTypes(for: pasteboard)
		let newItems = (extraItems ?? []).map { NSPasteboard.PasteboardType($0.typeIdentifier) }
		types.insert(contentsOf: newItems, at: 0)
		let fileURLType = NSPasteboard.PasteboardType(rawValue: "public.file-url")
		if !types.contains(fileURLType), tempPath != nil {
			types.append(fileURLType)
		}
		return types
	}

	deinit {
		let fm = FileManager.default
		if let tempPath = tempPath, fm.fileExists(atPath: tempPath.path) {
			try? fm.removeItem(at: tempPath)
		}
	}

	public override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
		if type.rawValue == "public.data" {
			return super.writingOptions(forType: type, pasteboard: pasteboard)
		}
		return []
	}

	public override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
		let T = type.rawValue
		switch T {
		case "public.data", "com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.promised-file-name", "com.apple.pasteboard.promised-file-content-type", "com.apple.pasteboard.NSFilePromiseID":
			return super.pasteboardPropertyList(forType: type)
		default:
			let item = extraItems?.first { $0.typeIdentifier == T }
			if item == nil && T == "public.file-url", let component = component, let tempPath = tempPath {
				do {
					try component.writeBytes(to: tempPath)
				} catch {
					log("Could not create drop data: \(error.localizedDescription)")
				}
				return tempPath.absoluteString.data(using: .utf8)
			} else {
				return item?.bytes
			}
		}
	}
}

final class GladysFileProviderDelegate: NSObject, NSFilePromiseProviderDelegate {

	private weak var typeItem: ArchivedDropItemType?
	private let title: String
	private let tempPath: URL

	init(item: ArchivedDropItemType, title: String, tempPath: URL) {
		typeItem = item
		self.title = title
		self.tempPath = tempPath
		super.init()
	}

	func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
		return title
	}

	func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
		do {
			let fm = FileManager.default
			if !fm.fileExists(atPath: tempPath.path) {
				try typeItem?.writeBytes(to: tempPath)
			}
			if fm.fileExists(atPath: url.path) {
				try fm.removeItem(at: url)
			}
			try fm.moveItem(at: tempPath, to: url)
			completionHandler(nil)
		}
		catch {
			completionHandler(error)
		}
	}
}

extension ArchivedDropItemType {
	func writeBytes(to destinationUrl: URL) throws {

		let bytesToWrite: Data?

		if isWebURL, let s = encodedUrl {
			bytesToWrite = s.urlFileContent
		} else {
			bytesToWrite = dataForWrappedItem
		}

		let fm = FileManager.default
		if fm.fileExists(atPath: destinationUrl.path) {
			try fm.removeItem(at: destinationUrl)
		}

		if let bytesToWrite = bytesToWrite {
			try bytesToWrite.write(to: destinationUrl)
		} else {
			try fm.linkItem(at: bytesPath, to: destinationUrl)
		}
	}
}
