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

final class CloudManager {

	struct RecordType {
		static let item = "ArchivedDropItem"
		static let component = "ArchivedDropItemType"
		static let positionList = "PositionList"
		static let share = "cloudkit.share"
	}
	
	static let privateDatabaseSubscriptionId = "private-changes"
	static let sharedDatabaseSubscriptionId = "shared-changes"
	static let legacyZoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

	static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

	static func go(_ operation: CKDatabaseOperation) {
		operation.qualityOfService = .userInitiated
		container.privateCloudDatabase.add(operation)
	}

	static func goShared(_ operation: CKDatabaseOperation) {
		operation.qualityOfService = .userInitiated
		container.sharedCloudDatabase.add(operation)
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

	static private func sequenceNeedsUpload(_ currentSequence: [String]) -> Bool {
		var previousSequence = uuidSequence
		for localItem in currentSequence {
			if !previousSequence.contains(localItem) { // we have a new item
				return true
			}
		}
		previousSequence = previousSequence.filter { currentSequence.contains($0) }
		return currentSequence != previousSequence
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

		let zoneId = legacyZoneId

		var idsToPush = [String]()
		var dataItemsToPush = 0
		var dropsToPush = 0
		var uuid2progress = [String: Progress]()

		let drops = Model.drops
		var payloadsToPush = drops.compactMap { item -> [CKRecord]? in
			guard let itemRecord = item.populatedCloudKitRecord else { return nil }
			if itemRecord.recordID.zoneID != zoneId {
				return nil // don't push changes to items shared by another user in this pass, for now // TODO
			}
			dataItemsToPush += item.typeItems.count
			dropsToPush += 1
			var payload = item.typeItems.compactMap { $0.populatedCloudKitRecord }
			payload.append(itemRecord)

			let itemId = item.uuid.uuidString
			idsToPush.append(itemId)
			uuid2progress[itemId] = Progress(totalUnitCount: 100)
			item.typeItems.forEach { uuid2progress[$0.uuid.uuidString] = Progress(totalUnitCount: 100) }

			return payload

		}.flatBunch(minSize: 10)

		var deletionIdsSnapshot = deletionQueue
		if idsToPush.count > 0 {
			let previousCount = deletionIdsSnapshot.count
			deletionIdsSnapshot = deletionIdsSnapshot.filter { !idsToPush.contains($0) }
			if deletionIdsSnapshot.count != previousCount {
				deletionQueue = deletionIdsSnapshot
			}
		}

		let currentUUIDSequence = drops.map { $0.uuid.uuidString }
		if sequenceNeedsUpload(currentUUIDSequence) {

			var sequenceToSend: [String]?

			if lastSyncCompletion == .distantPast {
				if currentUUIDSequence.count > 0 {
					var mergedSequence = uuidSequence
					for i in currentUUIDSequence.reversed() {
						if !mergedSequence.contains(i) {
							mergedSequence.insert(i, at: 0)
						}
					}
					sequenceToSend = mergedSequence
				}
			} else {
				sequenceToSend = currentUUIDSequence
			}

			if let sequenceToSend = sequenceToSend {
				let record = uuidSequenceRecord ?? CKRecord(recordType: RecordType.positionList, recordID: CKRecordID(recordName: RecordType.positionList, zoneID: zoneId))
				record["positionList"] = sequenceToSend as NSArray
				if payloadsToPush.count > 0 {
					payloadsToPush[0].insert(record, at: 0)
				} else {
					payloadsToPush.append([record])
				}
			}
		}

		let recordsToDelete = deletionIdsSnapshot.map { CKRecordID(recordName: $0, zoneID: zoneId) }.bunch(maxSize: 100)

		if payloadsToPush.count == 0 && recordsToDelete.count == 0 {
			log("No further changes to push up")
			#if MAINAPP
			CloudManager.shareActionIsActioningIds = []
			#endif
			completion(nil)
			return nil
		}

		let progress = Progress(totalUnitCount: Int64(dropsToPush + dataItemsToPush) * 100)
		for (k, v) in uuid2progress {
			progress.addChild(v, withPendingUnitCount: 100)
		}
		syncProgressString = "Sending changes"

		var latestError: Error?
		var operations = [CKDatabaseOperation]()

		log("Pushing up \(recordsToDelete.count) item deletion blocks")

		for recordIdList in recordsToDelete {
			let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIdList)
			operation.savePolicy = .allKeys
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						latestError = error
						log("Error deleting items: \(error.finalDescription)")
					}
					for uuid in (deletedRecordIds?.map({ $0.recordName })) ?? [] {
						if deletionIdsSnapshot.contains(uuid) {
							deletionQueue.remove(uuid)
							log("Deleted cloud record \(uuid)")
						}
					}
					updateSyncMessage()
				}
			}
			operations.append(operation)
		}

		log("Pushing up \(payloadsToPush.count) item blocks")

		func updateSyncMessage() {
			var components = [String]()
			if dropsToPush > 0 { components.append(dropsToPush == 1 ? "1 Drop" : "\(dropsToPush) Drops") }
			if dataItemsToPush > 0 { components.append(dataItemsToPush == 1 ? "1 Component" : "\(dataItemsToPush) Components") }
			let deletionCount = deletionQueue.count
			if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
			syncProgressString = "Sending" + (components.count > 0 ? (" " + components.joined(separator: ", ")) : "")
		}

		updateSyncMessage()

		for recordList in payloadsToPush {
			let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
			operation.savePolicy = .allKeys
			operation.isAtomic = true
			operation.perRecordProgressBlock = { record, progress in
				DispatchQueue.main.async {
					let recordProgress = uuid2progress[record.recordID.recordName]
					recordProgress?.completedUnitCount = Int64(progress * 100.0)
				}
			}
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error updating cloud records: \(error.finalDescription)")
						latestError = error
					}
					for record in updatedRecords ?? [] {
						let itemUUID = record.recordID.recordName
						if itemUUID == RecordType.positionList {
							uuidSequence = currentUUIDSequence
							uuidSequenceRecord = record
							log("Sent updated \(record.recordType) cloud record")
						} else if let item = Model.item(uuid: itemUUID) {
							item.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
							dropsToPush -= 1
						} else if let typeItem = Model.typeItem(uuid: itemUUID) {
							typeItem.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
							dataItemsToPush -= 1
						}
					}
					updateSyncMessage()
				}
			}
			operations.append(operation)
		}

		let group = DispatchGroup()
		operations.forEach {
			group.enter()
			$0.completionBlock = {
				group.leave()
			}
		}
		group.notify(queue: DispatchQueue.main) {
			#if MAINAPP
			CloudManager.shareActionIsActioningIds = []
			#endif
			completion(latestError)
		}
		operations.forEach {
			go($0)
		}

		return progress
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

	static var migratedSharing: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "migratedSharing")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "migratedSharing")
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

	static func markAsDeleted(uuid: UUID) {
		if syncSwitchedOn {
			deletionQueue.insert(uuid.uuidString)
		}
	}

}
