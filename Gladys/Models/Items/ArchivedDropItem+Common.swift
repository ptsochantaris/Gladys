//
//  ArchivedDropItem+Common.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CloudKit
#if os(iOS)
import UIKit
typealias IMAGE = UIImage
typealias COLOR = UIColor
#else
import Cocoa
typealias IMAGE = NSImage
typealias COLOR = NSColor
#endif

struct ImportOverrides {
	let title: String?
	let note: String?
	let labels: [String]?
}

let privateZoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

extension ArchivedDropItem: Hashable {

	static func == (lhs: ArchivedDropItem, rhs: ArchivedDropItem) -> Bool {
		return lhs.uuid == rhs.uuid
	}

	var hashValue: Int {
		return uuid.hashValue
	}

	var sizeInBytes: Int64 {
		return typeItems.reduce(0, { $0 + $1.sizeInBytes })
	}

	var imagePath: URL? {
		let highestPriorityIconItem = typeItems.max { $0.displayIconPriority < $1.displayIconPriority }
		return highestPriorityIconItem?.imagePath
	}

	var displayIcon: IMAGE {
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
		return nonOverridenText
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

	var imageCacheKey: NSString {
		return "\(uuid.uuidString) \(updatedAt.timeIntervalSinceReferenceDate)" as NSString
	}

	var nonOverridenText: (String?, NSTextAlignment) {
		if let a = typeItems.first(where: { $0.accessoryTitle != nil })?.accessoryTitle { return (a, .center) }

		let highestPriorityItem = typeItems.max { $0.displayTitlePriority < $1.displayTitlePriority }
		if let title = highestPriorityItem?.displayTitle {
			let alignment = highestPriorityItem?.displayTitleAlignment ?? .center
			return (title, alignment)
		} else {
			return (suggestedName, .center)
		}
	}

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

	var folderUrl: URL {
		let url = Model.appStorageUrl.appendingPathComponent(uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}

	private var cloudKitDataPath: URL {
		return folderUrl.appendingPathComponent("ck-record", isDirectory: false)
	}

	private var cloudKitShareDataPath: URL {
		return folderUrl.appendingPathComponent("ck-share", isDirectory: false)
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

	enum ShareMode {
		case none, elsewhereReadOnly, elsewhereReadWrite, sharing
	}

	var shareMode: ShareMode {
		if let shareRecord = cloudKitShareRecord {
			if shareRecord.recordID.zoneID == privateZoneId {
				return .sharing
			} else if let permission = cloudKitShareRecord?.currentUserParticipant?.permission, permission == .readWrite {
				return .elsewhereReadWrite
			} else {
				return .elsewhereReadOnly
			}
		} else {
			return .none
		}
	}

	var isShareWithOnlyOwner: Bool {
		if let shareRecord = cloudKitShareRecord {
			return shareRecord.participants.count == 1
				&& shareRecord.participants[0].userIdentity.userRecordID?.recordName == CKCurrentUserDefaultName
		}
		return false
	}

	var isPrivateShareWithOnlyOwner: Bool {
		if let shareRecord = cloudKitShareRecord {
			return shareRecord.participants.count == 1
				&& shareRecord.publicPermission == .none
				&& shareRecord.participants[0].userIdentity.userRecordID?.recordName == CKCurrentUserDefaultName
		}
		return false
	}

	var isImportedShare: Bool {
		switch shareMode {
		case .elsewhereReadOnly, .elsewhereReadWrite:
			return true
		case .none, .sharing:
			return false
		}
	}

	static let cloudKitRecordCache = NSCache<NSUUID, CKRecord>()
	var cloudKitRecord: CKRecord? {
		get {
			let nsuuid = uuid as NSUUID
			if let cachedValue = ArchivedDropItem.cloudKitRecordCache.object(forKey: nsuuid) {
				return cachedValue
			}

			let recordLocation = cloudKitDataPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = NSKeyedUnarchiver(forReadingWith: data)
				let record = CKRecord(coder: coder)
				if let record = record {
					ArchivedDropItem.cloudKitRecordCache.setObject(record, forKey: nsuuid)
				}
				return record
			} else {
				return nil
			}
		}
		set {
			let recordLocation = cloudKitDataPath
			let nsuuid = uuid as NSUUID
			if let newValue = newValue {
				ArchivedDropItem.cloudKitRecordCache.setObject(newValue, forKey: nsuuid)

				let data = NSMutableData()
				let coder = NSKeyedArchiver(forWritingWith: data)
				newValue.encodeSystemFields(with: coder)
				coder.finishEncoding()
				try? data.write(to: recordLocation, options: .atomic)

				needsCloudPush = false
			} else {
				ArchivedDropItem.cloudKitRecordCache.removeObject(forKey: nsuuid)
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			}
		}
	}

	private static let cloudKitShareCache = NSCache<NSUUID, CKShare>()
	var cloudKitShareRecord: CKShare? {
		get {
			let nsuuid = uuid as NSUUID
			if let cachedValue = ArchivedDropItem.cloudKitShareCache.object(forKey: nsuuid) {
				return cachedValue
			}

			let recordLocation = cloudKitShareDataPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = NSKeyedUnarchiver(forReadingWith: data)
				let record = CKShare(coder: coder)
				ArchivedDropItem.cloudKitShareCache.setObject(record, forKey: nsuuid)
				return record
			} else {
				return nil
			}
		}
		set {
			let recordLocation = cloudKitShareDataPath
			if let newValue = newValue {
				ArchivedDropItem.cloudKitShareCache.setObject(newValue, forKey: uuid as NSUUID)

				let data = NSMutableData()
				let coder = NSKeyedArchiver(forWritingWith: data)
				newValue.encodeSystemFields(with: coder)
				coder.finishEncoding()
				try? data.write(to: recordLocation, options: .atomic)
			} else {
				ArchivedDropItem.cloudKitShareCache.removeObject(forKey: uuid as NSUUID)
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			}
		}
	}

	static func clearCaches() {
		cloudKitRecordCache.removeAllObjects()
		cloudKitShareCache.removeAllObjects()
		for drop in Model.drops {
			for component in drop.typeItems {
				component.encodedURLCache = nil
			}
		}
	}
}
