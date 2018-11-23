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
	weak var delegate: ComponentIngestionDelegate?
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
	var contributedLabels: [String]?

	// Caches
	var encodedURLCache: (Bool, NSURL?)?
	var canPreviewCache: Bool?

	var displayIcon: NSImage? {
		set {
			dataAccessQueue.sync {
				let ipath = imagePath
				if let n = newValue, let data = n.tiffRepresentation {
					try? data.write(to: ipath)
				} else if FileManager.default.fileExists(atPath: ipath.path) {
					try? FileManager.default.removeItem(at: ipath)
				}
			}
		}
		get {
			var i: NSImage?
			dataAccessQueue.sync {
				i = NSImage(contentsOf: imagePath)
				i?.isTemplate = displayIconTemplate
			}
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
		setBytes(data)
	}

	init(typeIdentifier: String, parentUuid: UUID, delegate: ComponentIngestionDelegate, order: Int) {

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

		createdAt = record["createdAt"] as? Date ?? .distantPast
		updatedAt = record["updatedAt"] as? Date ?? .distantPast
		typeIdentifier = record["typeIdentifier"] as? String ?? "public.data"
		representedClass = RepresentedClass(name: record["representedClass"] as? String ?? "")
		classWasWrapped = ((record["classWasWrapped"] as? Int ?? 0) != 0)

		accessoryTitle = record["accessoryTitle"] as? String
		order = record["order"] as? Int ?? 0
		if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
			try? FileManager.default.copyAndReplaceItem(at: assetURL, to: bytesPath)
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
		setBytes(typeItem.bytes)
	}


	init(cloning item: ArchivedDropItemType, newParentUUID: UUID) {
		uuid = UUID()
		isTransferring = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		delegate = nil

		typeIdentifier = item.typeIdentifier
		parentUuid = newParentUUID
		order = item.order
		displayIconPriority = item.displayIconPriority
		displayIconContentMode = item.displayIconContentMode
		displayTitlePriority = item.displayTitlePriority
		displayTitleAlignment = item.displayTitleAlignment
		displayIconScale = item.displayIconScale
		displayIconWidth = item.displayIconWidth
		displayIconHeight = item.displayIconHeight
		displayIconTemplate = item.displayIconTemplate
		classWasWrapped = item.classWasWrapped
		representedClass = item.representedClass
		setBytes(item.bytes)
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

	private func handleFileUrl(_ item: URL, _ data: Data, _ storeBytes: Bool) {
		let resourceValues = try? item.resourceValues(forKeys: [.tagNamesKey])
		contributedLabels = resourceValues?.tagNames

		accessoryTitle = item.lastPathComponent
		let fm = FileManager.default
		var directory: ObjCBool = false
		if fm.fileExists(atPath: item.path, isDirectory: &directory) {
			do {
				if directory.boolValue {
					typeIdentifier = kUTTypeZipArchive as String
					setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)
					representedClass = .data
					let tempURL = Model.temporaryDirectoryUrl.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
					let a = Archive(url: tempURL, accessMode: .create)!
					let dirName = item.lastPathComponent
					let item = item.deletingLastPathComponent()
					try appendDirectory(item, chain: [dirName], archive: a, fm: fm)
					if loadingAborted {
						log("      Cancelled zip operation since ingest was aborted")
						return
					}
					try fm.moveAndReplaceItem(at: tempURL, to: bytesPath)
					log("      zipped files at url: \(item.absoluteString)")
					completeIngest()

				} else {
					let ext = item.pathExtension
					if !ext.isEmpty, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
						typeIdentifier = uti as String
					} else {
						typeIdentifier = kUTTypeData as String
					}
					representedClass = .data
					log("      read data from file url: \(item.absoluteString) - type assumed to be \(typeIdentifier)")
					let data = (try? Data(contentsOf: item, options: .mappedIfSafe)) ?? Data()
					handleData(data, resolveUrls: false, storeBytes)
				}

			} catch {
				if storeBytes {
					setBytes(data)
				}
				representedClass = .url
				log("      could not read data from file (\(error.localizedDescription)) treating as local file url: \(item.absoluteString)")
				setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
				completeIngest()
			}
		} else {
			if storeBytes {
				setBytes(data)
			}
			representedClass = .url
			log("      received local file url for non-existent file: \(item.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
			completeIngest()
		}
	}

	func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool) {

		setTitle(from: url)

		if url.isFileURL {
			handleFileUrl(url, data, storeBytes)

		} else {
			if storeBytes {
				setBytes(data)
			}
			representedClass = .url
			handleRemoteUrl(url, data, storeBytes)
		}
	}

	func removeIntents() {}

	func tryOpen(from viewController: NSViewController) {
		let shareItem = objectForShare

		if let shareItem = shareItem as? MKMapItem {
			shareItem.openInMaps(launchOptions: [:])

		} else if let contact = shareItem as? CNContact {
			let c = CNContactViewController(nibName: nil, bundle: nil)
			c.contact = contact
			viewController.presentAsModalWindow(c)

		} else if let item = shareItem as? URL {
			if !NSWorkspace.shared.open(item) {
				let message: String
				if item.isFileURL {
					message = "macOS does not recognise the type of this file"
				} else {
					message = "macOS does not recognise the type of this link"
				}
				genericAlert(title: "Can't Open", message: message)
			}
		} else {
			NSWorkspace.shared.openFile(bytesPath.path)
		}
	}

	func add(to pasteboardItem: NSPasteboardItem) {
		guard let b = bytes else { return }

		let tid = NSPasteboard.PasteboardType(typeIdentifier)
		if let e = encodedUrl {
			pasteboardItem.setData(e.dataRepresentation, forType: tid)
		} else {
			pasteboardItem.setData(b, forType: tid)
		}
	}

	func pasteboardItem(forDrag: Bool) -> NSPasteboardWriting {
		if forDrag {
			return GladysFilePromiseProvider.provider(for: self, with: oneTitle, extraItems: [self])
		} else {
			let pi = NSPasteboardItem()
			add(to: pi)
			return pi
		}
	}

	var quickLookItem: PreviewItem {
		return PreviewItem(typeItem: self)
	}

	var canPreview: Bool {
		if let canPreviewCache = canPreviewCache {
			return canPreviewCache
		}
		let res = fileExtension != nil && !(parent?.needsUnlock ?? true)
		canPreviewCache = res
		return res
	}

	func scanForBlobChanges() -> Bool {
		var detectedChange = false
		dataAccessQueue.sync {
			let recordLocation = bytesPath
			let fm = FileManager.default
			guard fm.fileExists(atPath: recordLocation.path) else { return }

			if let blobModification = Model.modificationDate(for: recordLocation) {
				if let recordedModification = lastGladysBlobUpdate { // we've already stamped this
					if recordedModification < blobModification { // is the file modified after we stamped it?
						lastGladysBlobUpdate = Date()
						detectedChange = true
					}
				} else {
					lastGladysBlobUpdate = Date() // have modification date but no stamp
				}
			} else {
				let now = Date()
				try? fm.setAttributes([FileAttributeKey.modificationDate: now], ofItemAtPath: recordLocation.path)
				lastGladysBlobUpdate = now // no modification date, no stamp
			}
		}
		return detectedChange
	}

	private static let lastModificationKey = "build.bru.Gladys.lastGladysModification"
	var lastGladysBlobUpdate: Date? { // be sure to protect with dataAccessQueue
		get {
			let recordLocation = bytesPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				return recordLocation.withUnsafeFileSystemRepresentation { fileSystemPath in
					let length = getxattr(fileSystemPath, ArchivedDropItemType.lastModificationKey, nil, 0, 0, 0)
					if length > 0 {
						var data = Data(count: length)
						let result = data.withUnsafeMutableBytes {
							getxattr(fileSystemPath, ArchivedDropItemType.lastModificationKey, $0, length, 0, 0)
						}
						if result > 0, let dateString = String(data: data, encoding: .utf8), let time = TimeInterval(dateString) {
							return Date(timeIntervalSinceReferenceDate: time)
						}
					}
					return nil
				}
			}
			return nil
		}
		set {
			let recordLocation = bytesPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				return recordLocation.withUnsafeFileSystemRepresentation { fileSystemPath in
					if let newValue = newValue {
						if let data = String(newValue.timeIntervalSinceReferenceDate).data(using: .utf8) {
							log("Setting external update stamp for \(recordLocation.path) to \(newValue)")
							_ = data.withUnsafeBytes {
								setxattr(fileSystemPath, ArchivedDropItemType.lastModificationKey, $0, data.count, 0, 0)
							}
						}
					} else {
						log("Clearing external update stamp for \(recordLocation.path)")
						removexattr(fileSystemPath, ArchivedDropItemType.lastModificationKey, 0)
					}
				}
			}
		}
	}
}
