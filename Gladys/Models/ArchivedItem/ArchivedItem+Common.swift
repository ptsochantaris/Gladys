//
//  ArchivedItem+Common.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

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

extension ArchivedItem: Hashable {
    static func == (lhs: ArchivedItem, rhs: ArchivedItem) -> Bool {
        lhs.uuid == rhs.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    var trimmedName: String {
        displayTitleOrUuid.truncateWithEllipses(limit: 32)
    }

    var trimmedSuggestedName: String {
        displayTitleOrUuid.truncateWithEllipses(limit: 128)
    }

    var sizeInBytes: Int64 {
        components.reduce(0) { $0 + $1.sizeInBytes }
    }

    var imagePath: URL? {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.imagePath
    }

    var displayIcon: IMAGE {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.componentIcon ?? #imageLiteral(resourceName: "iconStickyNote")
    }

    var dominantTypeDescription: String? {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.typeDescription
    }

    var displayMode: ArchivedDropItemDisplayType {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.displayIconContentMode ?? .center
    }

    var displayText: (String?, NSTextAlignment) {
        guard titleOverride.isEmpty else { return (titleOverride, .center) }
        return nonOverridenText
    }

    var displayTitleOrUuid: String {
        displayText.0 ?? uuid.uuidString
    }

    var isLocked: Bool {
        lockPassword != nil
    }

    var isTemporarilyUnlocked: Bool {
        isLocked && !flags.contains(.needsUnlock)
    }

    var associatedWebURL: URL? {
        for i in components {
            if let u = i.encodedUrl, !u.isFileURL {
                return u as URL
            }
        }
        return nil
    }

    var imageCacheKey: String {
        "\(uuid.uuidString) \(updatedAt.timeIntervalSinceReferenceDate)"
    }

    var nonOverridenText: (String?, NSTextAlignment) {
        if let a = components.first(where: { $0.accessoryTitle != nil })?.accessoryTitle { return (a, .center) }

        let highestPriorityItem = components.max { $0.displayTitlePriority < $1.displayTitlePriority }
        if let title = highestPriorityItem?.displayTitle {
            let alignment = highestPriorityItem?.displayTitleAlignment ?? .center
            return (title, alignment)
        } else {
            return (suggestedName, .center)
        }
    }

    func bytes(for type: String) -> Data? {
        components.first { $0.typeIdentifier == type }?.bytes
    }

    func url(for type: String) -> URL? {
        components.first { $0.typeIdentifier == type }?.encodedUrl
    }

    var isVisible: Bool {
        !needsDeletion && lockPassword == nil && !needsReIngest
    }

    func markUpdated() {
        updatedAt = Date()
        needsCloudPush = true
    }

    var folderUrl: URL {
        if let url = folderUrlCache[uuid] {
            return url as URL
        }

        let url = Model.appStorageUrl.appendingPathComponent(uuid.uuidString)
        let f = FileManager.default
        let path = url.path
        if !f.fileExists(atPath: path) {
            try! f.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
        folderUrlCache[uuid] = url
        return url
    }

    private var cloudKitDataPath: URL {
        if let url = cloudKitDataPathCache[uuid] {
            return url as URL
        }
        let url = folderUrl.appendingPathComponent("ck-record", isDirectory: false)
        cloudKitDataPathCache[uuid] = url
        return url
    }

    private var cloudKitShareDataPath: URL {
        if let url = cloudKitShareDataPathCache[uuid] {
            return url as URL
        }
        let url = folderUrl.appendingPathComponent("ck-share", isDirectory: false)
        cloudKitShareDataPathCache[uuid] = url
        return url
    }

    private static let needsCloudPushKey = "build.bru.Gladys.needsCloudPush"
    var needsCloudPush: Bool {
        get {
            let path = cloudKitDataPath
            return dataAccessQueue.sync {
                FileManager.default.getBoolAttribute(ArchivedItem.needsCloudPushKey, from: path) ?? true
            }
        }
        set {
            let path = cloudKitDataPath
            dataAccessQueue.async(flags: .barrier) {
                FileManager.default.setBoolAttribute(ArchivedItem.needsCloudPushKey, at: path, to: newValue)
            }
        }
    }

    enum ShareMode {
        case none, elsewhereReadOnly, elsewhereReadWrite, sharing
    }

    var isRecentlyAdded: Bool {
        createdAt.timeIntervalSinceNow > -86400 // 24h
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
            let recordLocation = cloudKitDataPath
            return dataAccessQueue.sync {
                if let cachedValue = cloudKitRecordCache[uuid] {
                    return cachedValue.record

                } else if let data = try? Data(contentsOf: recordLocation), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
                    let record = CKRecord(coder: coder)
                    coder.finishDecoding()
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: record)
                    return record

                } else {
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: nil)
                    return nil
                }
            }
        }
        set {
            let recordLocation = cloudKitDataPath
            let uuid = uuid
            dataAccessQueue.async(flags: .barrier) {
                if let newValue = newValue {
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: newValue)

                    let coder = NSKeyedArchiver(requiringSecureCoding: true)
                    newValue.encodeSystemFields(with: coder)
                    try? coder.encodedData.write(to: recordLocation)

                    self.needsCloudPush = false
                } else {
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: nil)
                    let f = FileManager.default
                    let path = recordLocation.path
                    if f.fileExists(atPath: path) {
                        try? f.removeItem(atPath: path)
                    }
                }
            }
        }
    }

    var cloudKitShareRecord: CKShare? {
        get {
            let uuid = uuid
            return dataAccessQueue.sync {
                if let cachedValue = cloudKitShareCache[uuid] {
                    return cachedValue.share

                } else if let data = try? Data(contentsOf: cloudKitShareDataPath), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
                    let share = CKShare(coder: coder)
                    coder.finishDecoding()
                    cloudKitShareCache[uuid] = CKShareCacheEntry(share: share)
                    return share

                } else {
                    cloudKitShareCache[uuid] = CKShareCacheEntry(share: nil)
                    return nil
                }
            }
        }
        set {
            let recordLocation = cloudKitShareDataPath
            let uuid = uuid
            dataAccessQueue.async(flags: .barrier) {
                if let newValue = newValue {
                    cloudKitShareCache[uuid] = CKShareCacheEntry(share: newValue)

                    let coder = NSKeyedArchiver(requiringSecureCoding: true)
                    newValue.encodeSystemFields(with: coder)
                    try? coder.encodedData.write(to: recordLocation)
                } else {
                    cloudKitShareCache[uuid] = CKShareCacheEntry(share: nil)
                    let f = FileManager.default
                    let path = recordLocation.path
                    if f.fileExists(atPath: path) {
                        try? f.removeItem(atPath: path)
                    }
                }
            }
        }
    }
}
