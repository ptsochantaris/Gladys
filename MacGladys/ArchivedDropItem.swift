//
//  ArchivedDropItem.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import CloudKit
import CoreSpotlight

final class ArchivedDropItem: Codable, Equatable {

	let suggestedName: String?
	let uuid: UUID
	let createdAt:  Date

	var typeItems: [ArchivedDropItemType] {
		didSet {
			needsSaving = true
		}
	}
	var updatedAt: Date {
		didSet {
			needsSaving = true
		}
	}
	var needsReIngest: Bool {
		didSet {
			needsSaving = true
		}
	}
	var needsDeletion: Bool {
		didSet {
			needsSaving = true
		}
	}
	var note: String {
		didSet {
			needsSaving = true
		}
	}
	var titleOverride: String {
		didSet {
			needsSaving = true
		}
	}
	var labels: [String] {
		didSet {
			needsSaving = true
		}
	}

	var lockPassword: Data? {
		didSet {
			needsSaving = true
		}
	}

	var lockHint: String? {
		didSet {
			needsSaving = true
		}
	}

	// Transient
	var loadingProgress: Progress?
	var needsSaving: Bool
	var needsUnlock: Bool

	private enum CodingKeys : String, CodingKey {
		case suggestedName
		case typeItems
		case createdAt
		case updatedAt
		case uuid
		case needsReIngest
		case note
		case titleOverride
		case labels
		case needsDeletion
		case lockPassword
		case lockHint
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encodeIfPresent(suggestedName, forKey: .suggestedName)
		try v.encode(createdAt, forKey: .createdAt)
		try v.encode(updatedAt, forKey: .updatedAt)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(typeItems, forKey: .typeItems)
		try v.encode(needsReIngest, forKey: .needsReIngest)
		try v.encode(note, forKey: .note)
		try v.encode(titleOverride, forKey: .titleOverride)
		try v.encode(labels, forKey: .labels)
		try v.encode(needsDeletion, forKey: .needsDeletion)
		try v.encodeIfPresent(lockPassword, forKey: .lockPassword)
		try v.encodeIfPresent(lockHint, forKey: .lockHint)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		suggestedName = try v.decodeIfPresent(String.self, forKey: .suggestedName)
		let c = try v.decode(Date.self, forKey: .createdAt)
		createdAt = c
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c
		uuid = try v.decode(UUID.self, forKey: .uuid)
		typeItems = try v.decode(Array<ArchivedDropItemType>.self, forKey: .typeItems)
		needsReIngest = try v.decodeIfPresent(Bool.self, forKey: .needsReIngest) ?? false
		note = try v.decodeIfPresent(String.self, forKey: .note) ?? ""
		titleOverride = try v.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
		labels = try v.decodeIfPresent([String].self, forKey: .labels) ?? []
		needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
		lockPassword = try v.decodeIfPresent(Data.self, forKey: .lockPassword)
		lockHint = try v.decodeIfPresent(String.self, forKey: .lockHint)
		needsSaving = false
		needsUnlock = lockPassword != nil
	}

	static func == (lhs: ArchivedDropItem, rhs: ArchivedDropItem) -> Bool {
		return lhs.uuid == rhs.uuid
	}

	var sizeInBytes: Int64 {
		return typeItems.reduce(0, { $0 + $1.sizeInBytes })
	}

	var imagePath: URL? {
		let highestPriorityIconItem = typeItems.max { $0.displayIconPriority < $1.displayIconPriority }
		return highestPriorityIconItem?.imagePath
	}

	var displayIcon: NSImage {
		let highestPriorityIconItem = typeItems.max { $0.displayIconPriority < $1.displayIconPriority }
		return highestPriorityIconItem?.displayIcon ?? #imageLiteral(resourceName: "iconStickyNote")
	}

	var dominantTypeDescription: String? {
		let highestPriorityIconItem = typeItems.max { $0.displayIconPriority < $1.displayIconPriority }
		return highestPriorityIconItem?.typeDescription
	}

	var displayMode: ArchivedDropItemDisplayType {
		let highestPriorityIconItem = typeItems.max { $0.displayIconPriority < $1.displayIconPriority }
		return highestPriorityIconItem?.displayIconContentMode ?? .center
	}

	var displayText: (String?, NSTextAlignment) {
		guard titleOverride.isEmpty else { return (titleOverride, .center) }
		if let a = typeItems.first(where: { $0.accessoryTitle != nil })?.accessoryTitle { return (a, .center) }

		let highestPriorityItem = typeItems.max { $0.displayTitlePriority < $1.displayTitlePriority }
		if let title = highestPriorityItem?.displayTitle {
			let alignment = highestPriorityItem?.displayTitleAlignment ?? .center
			return (title, alignment)
		} else {
			return (suggestedName, .center)
		}
	}

	var displayTitleOrUuid: String {
		return displayText.0 ?? uuid.uuidString
	}

	var isLocked: Bool {
		return lockPassword != nil
	}

	var associatedWebURL: URL? {
		for i in typeItems {
			if let u = i.encodedUrl, !u.isFileURL {
				return u as URL
			}
		}
		return nil
	}

	lazy var folderUrl: URL = {
		let url = Model.appStorageUrl.appendingPathComponent(self.uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try? f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}()

	func bytes(for type: String) -> Data? {
		return typeItems.first { $0.typeIdentifier == type }?.bytes
	}

	func url(for type: String) -> NSURL? {
		return typeItems.first { $0.typeIdentifier == type }?.encodedUrl
	}

	func markUpdated() {
		updatedAt = Date()
		needsCloudPush = true
	}

	#if MAINAPP || ACTIONEXTENSION

	static func importData(providers: [NSItemProvider], delegate: LoadCompletionDelegate?, overrides: ImportOverrides?) -> [ArchivedDropItem] {
		if PersistedOptions.separateItemPreference {
			var res = [ArchivedDropItem]()
			for p in providers {
				for t in sanitised(p.registeredTypeIdentifiers) {
					let item = ArchivedDropItem(providers: [p], delegate: delegate, limitToType: t, overrides: overrides)
					res.append(item)
				}
			}
			return res

		} else {
			let item = ArchivedDropItem(providers: providers, delegate: delegate, limitToType: nil, overrides: overrides)
			return [item]
		}
	}

	var loadCount = 0
	weak var delegate: LoadCompletionDelegate?

	private init(providers: [NSItemProvider], delegate: LoadCompletionDelegate?, limitToType: String?, overrides: ImportOverrides?) {

		uuid = UUID()
		createdAt = Date()
		updatedAt = createdAt
		suggestedName = providers.first!.suggestedName
		needsReIngest = true
		needsDeletion = false
		titleOverride = overrides?.title ?? ""
		note = overrides?.note ?? ""
		labels = overrides?.labels ?? []
		typeItems = [ArchivedDropItemType]()
		needsSaving = true
		needsUnlock = false

		loadingProgress = startIngest(providers: providers, delegate: delegate, limitToType: limitToType)
	}

	#endif

	init(from record: CKRecord, children: [CKRecord]) {
		let myUUID = UUID(uuidString: record.recordID.recordName)!
		uuid = myUUID
		createdAt = record["createdAt"] as! Date
		updatedAt = record["updatedAt"] as! Date
		suggestedName = record["suggestedName"] as? String
		titleOverride = record["titleOverride"] as! String
		lockPassword = record["lockPassword"] as? Data
		lockHint = record["lockHint"] as? String
		note = record["note"] as! String
		labels = (record["labels"] as? [String]) ?? []
		needsReIngest = true
		needsSaving = true
		needsDeletion = false
		needsUnlock = lockPassword != nil
		typeItems = children.map { ArchivedDropItemType(from: $0, parentUuid: myUUID) }.sorted { $0.order < $1.order }
		cloudKitRecord = record
	}

	var isDeleting = false

	var isTransferring: Bool {
		return typeItems.contains { $0.isTransferring }
	}

	var goodToSave: Bool { // TODO: Check if data transfer is occuring, NOT ingest
		return !isDeleting && !isTransferring
	}

	private var cloudKitDataPath: URL {
		return folderUrl.appendingPathComponent("ck-record", isDirectory: false)
	}

	var needsCloudPush: Bool {
		set {
			let recordLocation = cloudKitDataPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				_ = recordLocation.withUnsafeFileSystemRepresentation { fileSystemPath in
					if newValue {
						let data = "true".data(using: .utf8)!
						_ = data.withUnsafeBytes { bytes in
							setxattr(fileSystemPath, "build.bru.Gladys.needsCloudPush", bytes, data.count, 0, 0)
						}
					} else {
						removexattr(fileSystemPath, "build.bru.Gladys.needsCloudPush", 0)
					}
				}
			}
		}
		get {
			let recordLocation = cloudKitDataPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				return recordLocation.withUnsafeFileSystemRepresentation { fileSystemPath in
					let length = getxattr(fileSystemPath, "build.bru.Gladys.needsCloudPush", nil, 0, 0, 0)
					return length > 0
				}
			} else {
				return true
			}
		}
	}

	var cloudKitRecord: CKRecord? {
		get {
			let recordLocation = cloudKitDataPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = NSKeyedUnarchiver(forReadingWith: data)
				return CKRecord(coder: coder)
			} else {
				return nil
			}
		}
		set {
			let recordLocation = cloudKitDataPath
			if newValue == nil {
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			} else {
				let data = NSMutableData()
				let coder = NSKeyedArchiver(forWritingWith: data)
				newValue?.encodeSystemFields(with: coder)
				coder.finishEncoding()
				try? data.write(to: recordLocation, options: .atomic)

				needsCloudPush = false
			}
		}
	}

	func delete() {
		isDeleting = true
		if cloudKitRecord != nil {
			CloudManager.markAsDeleted(uuid: uuid)
		} else {
			log("No cloud record for this item, skipping cloud delete")
		}
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uuid.uuidString]) { error in
			if let error = error {
				log("Error while deleting an index \(error)")
			}
		}
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
	}
}
