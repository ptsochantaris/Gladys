//
//  CloudManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 21/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

#if os(iOS)
import UIKit
#else
import Cocoa
#endif
import CloudKit

let diskSizeFormatter = ByteCountFormatter()

extension Array {
	func bunch(maxSize: Int) -> [[Element]] {
		var pos = 0
		var res = [[Element]]()
		while pos < count {
			let end = Swift.min(count, pos + maxSize)
			let a = self[pos ..< end]
			res.append(Array(a))
			pos += maxSize
		}
		return res
	}
}

extension Array where Element == [CKRecord] {
	func flatBunch(minSize: Int) -> [[CKRecord]] {
		var result = [[CKRecord]]()
		var newChild = [CKRecord]()
		for childArray in self {
			newChild.append(contentsOf: childArray)
			if newChild.count >= minSize {
				result.append(newChild)
				newChild.removeAll(keepingCapacity: true)
			}
		}
		if newChild.count > 0 {
			result.append(newChild)
		}
		return result
	}
}

extension Error {
	var itemDoesNotExistOnServer: Bool {
		return (self as? CKError)?.code == CKError.Code.unknownItem
	}
}

final class CloudManager {

	struct RecordType {
		static let item = "ArchivedDropItem"
		static let component = "ArchivedDropItemType"
		static let positionList = "PositionList"
		static let share = "cloudkit.share"
	}
	
	static let privateDatabaseSubscriptionId = "private-changes"
	static let sharedDatabaseSubscriptionId = "shared-changes"

	static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

	static func perform(_ operation: CKDatabaseOperation) {
		operation.qualityOfService = .userInitiated
		operation.database!.add(operation)
	}

	static var syncDirty = false

	static var showNetwork: Bool = false {
		didSet {
			#if MAINAPP
			UIApplication.shared.isNetworkActivityIndicatorVisible = showNetwork
			#endif
			#if MAC
			NSApplication.shared.dockTile.badgeLabel = showNetwork ? "↔" : nil
			#endif
		}
	}

	static var syncProgressString: String? {
		didSet {
			#if DEBUG
			if let s = syncProgressString {
				log(">>> Sync update: \(s)")
			} else {
				log(">>> Sync updates done")
			}
			#endif
			NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
		}
	}

	@discardableResult
	static func sendUpdatesUp(completion: @escaping (Error?)->Void) -> Progress? {
		if !syncSwitchedOn {
			#if MAINAPP || ACTIONEXTENSION
			CloudManager.shareActionIsActioningIds = []
			#endif
			completion(nil)
			return nil
		}

		var sharedZonesToPush = Set<CKRecordZoneID>()
		for item in Model.drops where item.needsCloudPush {
			let zoneID = item.parentZone
			if zoneID != privateZoneId {
				sharedZonesToPush.insert(zoneID)
			}
		}

		let privatePushState = PushState(zoneId: privateZoneId, database: container.privateCloudDatabase)
		let sharedPushStates = sharedZonesToPush.map { PushState(zoneId: $0, database: container.sharedCloudDatabase) }

		let doneOperation = BlockOperation {
			#if MAINAPP
			CloudManager.shareActionIsActioningIds = []
			#endif
			let firstError = privatePushState.latestError ?? sharedPushStates.first(where: { $0.latestError != nil })?.latestError
			completion(firstError)
		}

		let operations = sharedPushStates.reduce(privatePushState.operations) { (existingOperations, pushState) -> [CKDatabaseOperation] in
			return existingOperations + pushState.operations
		}
		if operations.isEmpty {
			log("No changes to push up")
		} else {
			operations.forEach {
				doneOperation.addDependency($0)
				perform($0)
			}
		}
		OperationQueue.main.addOperation(doneOperation)

		let overallProgress = Progress(totalUnitCount: Int64(1+sharedPushStates.count) * 10)
		overallProgress.addChild(privatePushState.progress, withPendingUnitCount: 10)
		for pushState in sharedPushStates {
			overallProgress.addChild(pushState.progress, withPendingUnitCount: 10)
		}

		return overallProgress
	}

	static var syncTransitioning = false {
		didSet {
			if syncTransitioning != oldValue {
				showNetwork = syncing || syncTransitioning
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	static var syncRateLimited = false {
		didSet {
			if syncTransitioning != oldValue {
				syncProgressString = syncing ? "Pausing" : nil
				showNetwork = false
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	static var syncing = false {
		didSet {
			if syncing != oldValue {
				syncProgressString = syncing ? "Syncing" : nil
				showNetwork = syncing || syncTransitioning
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	typealias iCloudToken = (NSCoding & NSCopying & NSObjectProtocol)
	static var lastiCloudAccount: iCloudToken? {
		get {
			let o = PersistedOptions.defaults.object(forKey: "lastiCloudAccount") as? iCloudToken
			return (o?.isEqual("") ?? false) ? nil : o
		}
		set {
			if let n = newValue {
				PersistedOptions.defaults.set(n, forKey: "lastiCloudAccount")
			} else {
				PersistedOptions.defaults.set("", forKey: "lastiCloudAccount") // this will return nil when fetched
			}
			PersistedOptions.defaults.synchronize()
		}
	}

	static var lastSyncCompletion: Date {
		get {
			return PersistedOptions.defaults.object(forKey: "lastSyncCompletion") as? Date ?? .distantPast
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "lastSyncCompletion")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var syncSwitchedOn: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "syncSwitchedOn")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "syncSwitchedOn")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var shareActionShouldUpload: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "shareActionShouldUpload")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "shareActionShouldUpload")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var uuidSequence: [String] {
		get {
			if let data = PersistedOptions.defaults.data(forKey: "uuidSequence") {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String] ?? []
			} else {
				return []
			}
		}
		set {
			let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
			PersistedOptions.defaults.set(data, forKey: "uuidSequence")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var uuidSequenceRecordPath: URL {
		return Model.appStorageUrl.appendingPathComponent("ck-uuid-sequence", isDirectory: false)
	}

	static var uuidSequenceRecord: CKRecord? {
		get {
			let recordLocation = uuidSequenceRecordPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = NSKeyedUnarchiver(forReadingWith: data)
				return CKRecord(coder: coder)
			} else {
				return nil
			}
		}
		set {
			let recordLocation = uuidSequenceRecordPath
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
			}
		}
	}

	static var deleteQueuePath: URL {
		return Model.appStorageUrl.appendingPathComponent("ck-delete-queue", isDirectory: false)
	}

	static var deletionQueue: Set<String> {
		get {
			let recordLocation = deleteQueuePath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				return (NSKeyedUnarchiver.unarchiveObject(with: data) as? Set<String>) ?? []
			} else {
				return []
			}
		}
		set {
			let recordLocation = deleteQueuePath
			let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
			try? data.write(to: recordLocation, options: .atomic)
		}
	}

	private static func deletionTag(for uuid: UUID, cloudKitRecord: CKRecord?) -> String {
		if let zoneId = cloudKitRecord?.recordID.zoneID {
			return zoneId.zoneName + ":" + zoneId.ownerName + ":" + uuid.uuidString
		} else {
			return uuid.uuidString
		}
	}

	static func markAsDeleted(uuid: UUID, cloudKitRecord: CKRecord?) {
		if syncSwitchedOn {
			deletionQueue.insert(deletionTag(for: uuid, cloudKitRecord: cloudKitRecord))
		}
	}

	static func commitDeletion(for uuids: [String]) {
		if uuids.isEmpty { return }

		let newQueue = CloudManager.deletionQueue.filter { deletionTag in
			for uuid in uuids {
				if deletionTag.components(separatedBy: ":").last == uuid {
					return false
				}
			}
			return true
		}
		CloudManager.deletionQueue = newQueue
	}

}
