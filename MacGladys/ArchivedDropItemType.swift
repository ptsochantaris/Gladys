//
//  ArchivedDropItemType.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import CloudKit
import MapKit
import ZIPFoundation
import ContactsUI

final class ArchivedDropItemType: Codable {

	private enum CodingKeys : String, CodingKey {
		case typeIdentifier
		case representedClass
		case classWasWrapped
		case uuid
		case parentUuid
		case accessoryTitle
		case displayTitle
		case displayTitleAlignment
		case displayTitlePriority
		case displayIconPriority
		case displayIconContentMode
		case displayIconScale
		case displayIconWidth
		case displayIconHeight
		case displayIconTemplate
		case createdAt
		case updatedAt
		case needsDeletion
		case order
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encode(typeIdentifier, forKey: .typeIdentifier)
		try v.encode(representedClass, forKey: .representedClass)
		try v.encode(classWasWrapped, forKey: .classWasWrapped)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(parentUuid, forKey: .parentUuid)
		try v.encodeIfPresent(accessoryTitle, forKey: .accessoryTitle)
		try v.encodeIfPresent(displayTitle, forKey: .displayTitle)
		try v.encode(displayTitleAlignment.rawValue, forKey: .displayTitleAlignment)
		try v.encode(displayTitlePriority, forKey: .displayTitlePriority)
		try v.encode(displayIconContentMode.rawValue, forKey: .displayIconContentMode)
		try v.encode(displayIconPriority, forKey: .displayIconPriority)
		try v.encode(displayIconScale, forKey: .displayIconScale)
		try v.encode(displayIconWidth, forKey: .displayIconWidth)
		try v.encode(displayIconHeight, forKey: .displayIconHeight)
		try v.encode(createdAt, forKey: .createdAt)
		try v.encode(updatedAt, forKey: .updatedAt)
		try v.encode(displayIconTemplate, forKey: .displayIconTemplate)
		try v.encode(needsDeletion, forKey: .needsDeletion)
		try v.encode(order, forKey: .order)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		representedClass = try v.decode(RepresentedClass.self, forKey: .representedClass)
		classWasWrapped = try v.decode(Bool.self, forKey: .classWasWrapped)
		uuid = try v.decode(UUID.self, forKey: .uuid)
		parentUuid = try v.decode(UUID.self, forKey: .parentUuid)
		accessoryTitle = try v.decodeIfPresent(String.self, forKey: .accessoryTitle)
		displayTitle = try v.decodeIfPresent(String.self, forKey: .displayTitle)
		displayTitlePriority = try v.decode(Int.self, forKey: .displayTitlePriority)
		displayIconPriority = try v.decode(Int.self, forKey: .displayIconPriority)
		displayIconScale = try v.decode(CGFloat.self, forKey: .displayIconScale)
		displayIconWidth = try v.decode(CGFloat.self, forKey: .displayIconWidth)
		displayIconHeight = try v.decode(CGFloat.self, forKey: .displayIconHeight)
		displayIconTemplate = try v.decodeIfPresent(Bool.self, forKey: .displayIconTemplate) ?? false
		needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
		order = try v.decodeIfPresent(Int.self, forKey: .order) ?? 0

		let c = try v.decode(Date.self, forKey: .createdAt)
		createdAt = c
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c

		let a = try v.decode(UInt.self, forKey: .displayTitleAlignment)
		displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

		let m = try v.decode(Int.self, forKey: .displayIconContentMode)
		displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center

		isTransferring = false
	}

	var isArchivable: Bool {
		if let e = encodedUrl, !e.isFileURL, e.host != nil, let s = e.scheme, s.hasPrefix("http") {
			return true
		} else {
			return false
		}
	}

	var typeIdentifier: String
	var accessoryTitle: String?
	let uuid: UUID
	let parentUuid: UUID
	let createdAt: Date
	var updatedAt: Date
	var representedClass: RepresentedClass
	var classWasWrapped: Bool
	var loadingError: Error?
	var needsDeletion: Bool
	var order: Int

	// transient / ui
	weak var delegate: LoadCompletionDelegate?
	var displayIconScale: CGFloat
	var displayIconWidth: CGFloat
	var displayIconHeight: CGFloat
	var loadingAborted = false
	var displayIconPriority: Int
	var displayIconContentMode: ArchivedDropItemDisplayType
	var displayIconTemplate: Bool
	var displayTitle: String?
	var displayTitlePriority: Int
	var displayTitleAlignment: NSTextAlignment
	var ingestCompletion: (()->Void)?
	var isTransferring: Bool

	var displayIcon: NSImage? {
		set {
			let ipath = imagePath
			if let n = newValue, let data = n.tiffRepresentation {
				try? data.write(to: ipath)
			} else if FileManager.default.fileExists(atPath: ipath.path) {
				try? FileManager.default.removeItem(at: ipath)
			}
		}
		get {
			let i = NSImage(contentsOf: imagePath)
			i?.isTemplate = displayIconTemplate
			return i
		}
	}

	init(typeIdentifier: String, parentUuid: UUID, data: Data, order: Int) {

		self.typeIdentifier = typeIdentifier
		self.parentUuid = parentUuid
		self.order = order

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		classWasWrapped = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		representedClass = .data
		delegate = nil
		bytes = data
	}

	init(typeIdentifier: String, parentUuid: UUID, delegate: LoadCompletionDelegate, order: Int) {

		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.parentUuid = parentUuid
		self.order = order

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = true
		classWasWrapped = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		representedClass = .unknown(name: "")
	}

	init(from record: CKRecord, parentUuid: UUID) {

		self.parentUuid = parentUuid

		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		needsDeletion = false

		let myUUID = record.recordID.recordName
		uuid = UUID(uuidString: myUUID)!
		createdAt = record["createdAt"] as! Date
		updatedAt = record["updatedAt"] as! Date
		typeIdentifier = record["typeIdentifier"] as! String
		representedClass = RepresentedClass(name: record["representedClass"] as! String)
		classWasWrapped = (record["classWasWrapped"] as! Int != 0)
		accessoryTitle = record["accessoryTitle"] as? String
		order = record["order"] as? Int ?? 0
		if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
			let path = bytesPath
			let f = FileManager.default
			if f.fileExists(atPath: path.path) {
				try? f.removeItem(at: path)
			}
			try? f.copyItem(at: assetURL, to: path)
		}
		cloudKitRecord = record
	}

	init(from typeItem: ArchivedDropItemType, newParent: ArchivedDropItem) {
		parentUuid = newParent.uuid

		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		needsDeletion = false
		order = Int.max
		delegate = nil

		uuid = UUID()
		createdAt = Date()
		updatedAt = Date()
		typeIdentifier = typeItem.typeIdentifier
		representedClass = typeItem.representedClass
		classWasWrapped = typeItem.classWasWrapped
		accessoryTitle = typeItem.accessoryTitle
		bytes = typeItem.bytes
	}

	private func appendDirectory(_ baseURL: URL, chain: [String], archive: Archive, fm: FileManager) throws {
		let joinedChain = chain.joined(separator: "/")
		let dirURL = baseURL.appendingPathComponent(joinedChain)
		for file in try fm.contentsOfDirectory(atPath: dirURL.path) {
			if loadingAborted {
				log("      Interrupted zip operation since ingest was aborted")
				break
			}
			let newURL = dirURL.appendingPathComponent(file)
			var directory: ObjCBool = false
			if fm.fileExists(atPath: newURL.path, isDirectory: &directory) {
				if directory.boolValue {
					var newChain = chain
					newChain.append(file)
					try appendDirectory(baseURL, chain: newChain, archive: archive, fm: fm)
				} else {
					log("      Compressing \(newURL.path)")
					let path = joinedChain + "/" + file
					try archive.addEntry(with: path, relativeTo: baseURL)
				}
			}
		}
	}

	func handleUrl(_ item: URL, _ data: Data) {

		setTitle(from: item)

		if item.isFileURL {
			let fm = FileManager.default
			var directory: ObjCBool = false
			if fm.fileExists(atPath: item.path, isDirectory: &directory) {
				do {
					let data: Data
					if directory.boolValue {
						typeIdentifier = kUTTypeZipArchive as String
						setDisplayIcon(#imageLiteral(resourceName: "zip"), 5, .center)

						let tempURL = Model.temporaryDirectoryUrl.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
						let a = Archive(url: tempURL, accessMode: .create)!
						let dirName = item.lastPathComponent
						let item = item.deletingLastPathComponent()
						try appendDirectory(item, chain: [dirName], archive: a, fm: fm)
						if loadingAborted {
							log("      Cancelled zip operation since ingest was aborted")
							return
						}
						data = try Data(contentsOf: tempURL)
						try? fm.removeItem(at: tempURL)
					} else {
						data = try Data(contentsOf: item)
						let ext = item.pathExtension
						if !ext.isEmpty, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
							typeIdentifier = uti as String
						} else {
							typeIdentifier = kUTTypeData as String
						}
						setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
					}
					accessoryTitle = item.lastPathComponent
					representedClass = .data
					log("      read data from file url: \(item.absoluteString) - type assumed to be \(typeIdentifier)")
					handleData(data)

				} catch {
					bytes = data
					representedClass = .url
					log("      could not read data from file (\(error.localizedDescription)) treating as local file url: \(item.absoluteString)")
					setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
					completeIngest()
				}
			} else {
				bytes = data
				representedClass = .url
				log("      received local file url for non-existent file: \(item.absoluteString)")
				setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
				completeIngest()
			}

		} else {
			bytes = data
			representedClass = .url

			log("      received remote url: \(item.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
			if let s = item.scheme, s.hasPrefix("http") {
				fetchWebPreview(for: item) { [weak self] title, image in
					if self?.loadingAborted ?? true { return }
					self?.accessoryTitle = title ?? self?.accessoryTitle
					if let image = image {
						if image.size.height > 100 || image.size.width > 200 {
							self?.setDisplayIcon(image, 30, .fit)
						} else {
							self?.setDisplayIcon(image, 30, .center)
						}
					}
					self?.completeIngest()
				}
			} else {
				completeIngest()
			}
		}
	}

	func tryOpen(from viewController: NSViewController) {
		let shareItem = objectForShare

		if let shareItem = shareItem as? MKMapItem {
			shareItem.openInMaps(launchOptions: [:])

		} else if let contact = shareItem as? CNContact {
			let c = CNContactViewController(nibName: nil, bundle: nil)
			c.contact = contact
			viewController.presentViewControllerAsModalWindow(c)

		} else if let item = shareItem as? URL {
			if !NSWorkspace.shared.open(item) {
				let message: String
				if item.isFileURL {
					message = "macOS does not recognise the type of this file"
				} else {
					message = "macOS does not recognise the type of this link"
				}
				genericAlert(title: "Can't Open", message: message, on: viewController)
			}
		} else {
			NSWorkspace.shared.openFile(bytesPath.path)
		}
	}

	func add(to pasteboardItem: NSPasteboardItem) {
		guard let b = bytes else { return }
		let tid = NSPasteboard.PasteboardType(typeIdentifier)
		if let e = encodedUrl, let s = e.absoluteString {
			pasteboardItem.setString(s, forType: tid)
		} else {
			pasteboardItem.setData(b, forType: tid)
		}
	}

	var pasteboardItem: NSPasteboardItem {
		let pi = NSPasteboardItem()
		add(to: pi)
		return pi
	}

	var filePromise: GladysFilePromiseProvider? {
		if typeConforms(to: kUTTypeContent) || typeConforms(to: kUTTypeItem) {
			return GladysFilePromiseProvider(dropItemType: self, title: displayTitle ?? typeIdentifier)
		} else {
			return nil
		}
	}

	var imagePath: URL {
		return folderUrl.appendingPathComponent("thumbnail.png")
	}

	var bytesPath: URL {
		return folderUrl.appendingPathComponent("blob", isDirectory: false)
	}

	var folderUrl: URL {
		let url = Model.appStorageUrl.appendingPathComponent(parentUuid.uuidString).appendingPathComponent(uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}

	var quickLookItem: PreviewItem {
		return PreviewItem(typeItem: self)
	}

	var parent: ArchivedDropItem? {
		return Model.item(uuid: parentUuid)
	}

	var canPreview: Bool {
		return fileExtension != nil && !(parent?.needsUnlock ?? true)
	}
}
