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

let privateZoneId = CKRecordZone.ID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

extension ArchivedDropItem: Hashable {

	static func == (lhs: ArchivedDropItem, rhs: ArchivedDropItem) -> Bool {
		return lhs.uuid == rhs.uuid
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(uuid)
	}

	var trimmedName: String {
		return displayTitleOrUuid.truncateWithEllipses(limit: 32)
	}

	var trimmedSuggestedName: String {
		return displayTitleOrUuid.truncateWithEllipses(limit: 128)
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

	var isTemporarilyUnlocked: Bool {
		return isLocked && !needsUnlock
	}

	var associatedWebURL: URL? {
		for i in typeItems {
			if let u = i.encodedUrl, !u.isFileURL {
				return u as URL
			}
		}
		return nil
	}
    
    var loadingError: (String, Error)? {
        for item in typeItems {
            if let e = item.loadingError {
                return ("Error processing type \(item.typeIdentifier): ", e)
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

	var isVisible: Bool {
		return !needsDeletion && lockPassword == nil && !needsReIngest
	}

	func markUpdated() {
		updatedAt = Date()
		needsCloudPush = true
	}

	var folderUrl: URL {
		let nsuuiud = uuid as NSUUID
		if let url = folderUrlCache.object(forKey: nsuuiud) {
			return url as URL
		}

		let url = Model.appStorageUrl.appendingPathComponent(uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		folderUrlCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}

	private var cloudKitDataPath: URL {
		let nsuuiud = uuid as NSUUID
		if let url = cloudKitDataPathCache.object(forKey: nsuuiud) {
			return url as URL
		}
		let url = folderUrl.appendingPathComponent("ck-record", isDirectory: false)
		cloudKitDataPathCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}

	private var cloudKitShareDataPath: URL {
		let nsuuiud = uuid as NSUUID
		if let url = cloudKitShareDataPathCache.object(forKey: nsuuiud) {
			return url as URL
		}
		let url = folderUrl.appendingPathComponent("ck-share", isDirectory: false)
		cloudKitShareDataPathCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}

	private static let needsCloudPushKey = "build.bru.Gladys.needsCloudPush"
	var needsCloudPush: Bool {
		set {
            FileManager.default.setBoolAttribute(ArchivedDropItem.needsCloudPushKey, at: cloudKitDataPath, to: newValue)
		}
		get {
            return FileManager.default.getBoolAttribute(ArchivedDropItem.needsCloudPushKey, from: cloudKitDataPath) ?? true
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

	var cloudKitRecord: CKRecord? {
		get {
			let nsuuid = uuid as NSUUID
			if let cachedValue = cloudKitRecordCache.object(forKey: nsuuid) {
				return cachedValue.record
			}

			let recordLocation = cloudKitDataPath
			let record: CKRecord?
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = try! NSKeyedUnarchiver(forReadingFrom: data)
				record = CKRecord(coder: coder)
				coder.finishDecoding()
			} else {
				record = nil
			}
			cloudKitRecordCache.setObject(CKRecordCacheEntry(record: record), forKey: nsuuid)
			return record
		}
		set {
			let recordLocation = cloudKitDataPath
			let nsuuid = uuid as NSUUID
			if let newValue = newValue {
				cloudKitRecordCache.setObject(CKRecordCacheEntry(record: newValue), forKey: nsuuid)

				let coder = NSKeyedArchiver(requiringSecureCoding: true)
				newValue.encodeSystemFields(with: coder)
				try? coder.encodedData.write(to: recordLocation, options: .atomic)

				needsCloudPush = false
			} else {
				cloudKitRecordCache.setObject(CKRecordCacheEntry(record: nil), forKey: nsuuid)
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			}
		}
	}

	var cloudKitShareRecord: CKShare? {
		get {
			let nsuuid = uuid as NSUUID
			if let cachedValue = cloudKitShareCache.object(forKey: nsuuid) {
				return cachedValue.share
			}

			let recordLocation = cloudKitShareDataPath
			let share: CKShare?
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = try! NSKeyedUnarchiver(forReadingFrom: data)
				share = CKShare(coder: coder)
				coder.finishDecoding()
			} else {
				share = nil
			}
			cloudKitShareCache.setObject(CKShareCacheEntry(share: share), forKey: nsuuid)
			return share
		}
		set {
			let recordLocation = cloudKitShareDataPath
			let nsuuid = uuid as NSUUID
			if let newValue = newValue {
				cloudKitShareCache.setObject(CKShareCacheEntry(share: newValue), forKey: nsuuid)

				let coder = NSKeyedArchiver(requiringSecureCoding: true)
				newValue.encodeSystemFields(with: coder)
				try? coder.encodedData.write(to: recordLocation, options: .atomic)
			} else {
				cloudKitShareCache.setObject(CKShareCacheEntry(share: nil), forKey: nsuuid)
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			}
		}
	}
}
