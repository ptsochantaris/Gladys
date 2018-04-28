//
//  CloudManager.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import CloudKit

final class CloudManager {

	static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

	static func go(_ operation: CKDatabaseOperation) {
		operation.qualityOfService = .userInitiated
		container.privateCloudDatabase.add(operation)
	}

	static var syncDirty = false

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

	/////////////////////////////////////////////

	private static func sequenceNeedsUpload(_ currentSequence: [String]) -> Bool {
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
			completion(nil)
			return nil
		}

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

		var idsToPush = [String]()
		var dataItemsToPush = 0
		var dropsToPush = 0
		var uuid2progress = [String: Progress]()

		let drops = Model.drops
		var payloadsToPush = drops.compactMap { item -> [CKRecord]? in
			if let itemRecord = item.populatedCloudKitRecord {
				dataItemsToPush += item.typeItems.count
				dropsToPush += 1
				var payload = item.typeItems.compactMap { $0.populatedCloudKitRecord }
				payload.append(itemRecord)

				let itemId = item.uuid.uuidString
				idsToPush.append(itemId)
				uuid2progress[itemId] = Progress(totalUnitCount: 100)
				item.typeItems.forEach { uuid2progress[$0.uuid.uuidString] = Progress(totalUnitCount: 100) }

				return payload
			}
			return nil
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
				let record = uuidSequenceRecord ?? CKRecord(recordType: "PositionList", recordID: CKRecordID(recordName: "PositionList", zoneID: zoneId))
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
						if itemUUID == "PositionList" {
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
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	static var syncRateLimited = false {
		didSet {
			if syncTransitioning != oldValue {
				syncProgressString = syncing ? "Pausing" : nil
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	static var syncing = false {
		didSet {
			if syncing != oldValue {
				syncProgressString = syncing ? "Syncing" : nil
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

	static var onlySyncOverWiFi: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "onlySyncOverWiFi")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "onlySyncOverWiFi")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var zoneChangeToken: CKServerChangeToken? {
		get {
			if let data = PersistedOptions.defaults.data(forKey: "zoneChangeToken"), data.count > 0 {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
			} else {
				return nil
			}
		}
		set {
			if let n = newValue {
				let data = NSKeyedArchiver.archivedData(withRootObject: n)
				PersistedOptions.defaults.set(data, forKey: "zoneChangeToken")
			} else {
				PersistedOptions.defaults.set(Data(), forKey: "zoneChangeToken")
			}
			PersistedOptions.defaults.synchronize()
		}
	}

	///////////////////////////////////////

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

	///////////////////////////////////

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

	//////////////////////////////////////////////// UI

	private static let agoFormatter: DateComponentsFormatter = {
		let f = DateComponentsFormatter()
		f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
		f.unitsStyle = .abbreviated
		f.maximumUnitCount = 2
		return f
	}()

	static var syncString: String {
		if let s = syncProgressString {
			return s
		}

		if syncRateLimited { return "Pausing" }
		if syncTransitioning { return syncSwitchedOn ? "Deactivating" : "Activating" }

		let i = -lastSyncCompletion.timeIntervalSinceNow
		if i < 1.0 {
			return "Synced"
		} else if lastSyncCompletion != .distantPast, let s = agoFormatter.string(from: i) {
			return "Synced \(s) ago"
		} else {
			return "Never"
		}
	}

	/////////////////////////////////////////////////// Push

	static func received(notificationInfo: [AnyHashable : Any]) {
		NSApplication.shared.dockTile.badgeLabel = nil
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			Model.reloadDataIfNeeded()
			sync { error in
				if let error = error {
					log("Push sync result: \(error.finalDescription)")
				} else {
					log("Push sync done")
				}
			}
		}
	}

	///////////////////////////////////////////////// Activation

	static func activate(completion: @escaping (Error?)->Void) {

		if syncSwitchedOn {
			completion(nil)
			return
		}

		syncTransitioning = true
		container.accountStatus { status, error in
			DispatchQueue.main.async {
				if status == .available {
					log("User has iCloud, can activate cloud sync")
					proceedWithActivation { error in
						completion(error)
						syncTransitioning = false
					}
				} else {
					syncTransitioning = false
					log("User not logged into iCloud")
					if let error = error {
						completion(error)
					} else {
						completion(NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "You are not logged into iCloud on this device."]))
					}
				}
			}
		}
	}

	static func deactivate(force: Bool, completion: @escaping (Error?)->Void) {
		syncTransitioning = true
		let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: ["private-changes"])
		ms.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			DispatchQueue.main.async {
				if let error = error, !force {
					log("Cloud sync deactivation failed")
					completion(error)
				} else {
					deletionQueue.removeAll()
					lastSyncCompletion = .distantPast
					uuidSequence = []
					uuidSequenceRecord = nil
					zoneChangeToken = nil
					syncSwitchedOn = false
					lastiCloudAccount = nil
					NSApplication.shared.unregisterForRemoteNotifications()
					for item in Model.drops {
						item.cloudKitRecord = nil
						for typeItem in item.typeItems {
							typeItem.cloudKitRecord = nil
						}
					}
					Model.save()
					log("Cloud sync deactivation complete")
					completion(nil)
				}
				syncTransitioning = false
			}
		}
		go(ms)
	}

	private static func proceedWithActivation(completion: @escaping (Error?)->Void) {

		NSApplication.shared.registerForRemoteNotifications(matching: [.badge])

		let zone = CKRecordZone(zoneName: "archivedDropItems")
		let createZone = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
		createZone.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
			if let error = error {
				log("Error while creating zone: \(error.finalDescription)")
				DispatchQueue.main.async {
					completion(error)
				}
			}
		}

		let notificationInfo = CKNotificationInfo()
		notificationInfo.shouldSendContentAvailable = true
		notificationInfo.shouldBadge = true

		let subscription = CKDatabaseSubscription(subscriptionID: "private-changes")
		subscription.notificationInfo = notificationInfo

		let subscribeToZone = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
		subscribeToZone.addDependency(createZone)
		subscribeToZone.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				log("Error while updating zone subscription: \(error.finalDescription)")
				DispatchQueue.main.async {
					completion(error)
				}
			}
		}

		let positionListId = CKRecordID(recordName: "PositionList", zoneID: zone.zoneID)
		let fetchInitialUUIDSequence = CKFetchRecordsOperation(recordIDs: [positionListId])
		fetchInitialUUIDSequence.addDependency(subscribeToZone)
		fetchInitialUUIDSequence.fetchRecordsCompletionBlock = { ids2records, error in
			DispatchQueue.main.async {
				if let error = error, (error as? CKError)?.code != CKError.partialFailure {
					log("Error while fetching inital item sequence: \(error.finalDescription)")
					completion(error)
				} else {
					if let sequenceRecord = ids2records?[positionListId], let sequence = sequenceRecord["positionList"] as? [String] {
						log("Received initial record sequence")
						uuidSequence = sequence
						uuidSequenceRecord = sequenceRecord
					} else {
						log("No initial record sequence on server")
						uuidSequence = []
					}
					syncSwitchedOn = true
					lastiCloudAccount = FileManager.default.ubiquityIdentityToken
					sync(force: true, completion: completion)
				}
			}
		}

		go(createZone)
		go(subscribeToZone)
		go(fetchInitialUUIDSequence)
	}

	/////////////////////////////////////////// Wipe Zone

	static func eraseZoneIfNeeded(completion: @escaping (Error?)->Void) {
		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)
		let deleteZone = CKModifyRecordZonesOperation(recordZonesToSave:nil, recordZoneIDsToDelete: [zoneId])
		deleteZone.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
			if let error = error {
				log("Error while deleting zone: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				completion(error)
			}
		}
		go(deleteZone)
	}

	/////////////////////////////////////////// Fetching

	private static func fetchDatabaseChanges(finalCompletion: @escaping (Error?)->Void) {

		var updatedSequence = false
		var newDrops = [CKRecord]()
		var newTypeItemsToHookOntoDrops = [CKRecord]()

		var typeUpdateCount = 0
		var deletionCount = 0
		var updateCount = 0
		syncProgressString = "Fetching"

		func updateProgress() {
			var components = [String]()

			let newCount = newDrops.count
			if newCount > 0 { components.append(newCount == 1 ? "1 Drop" : "\(newCount) Drops") }
			if updateCount > 0 { components.append(updateCount == 1 ? "1 Update" : "\(updateCount) Updates") }

			let newTypeCount = newTypeItemsToHookOntoDrops.count
			if newTypeCount > 0 { components.append(newCount == 1 ? "1 Component" : "\(newTypeCount) Components") }
			if typeUpdateCount > 0 { components.append(newCount == 1 ? "1 Component Update" : "\(typeUpdateCount) Component Updates") }

			if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
			if components.count > 0 {
				syncProgressString = "Fetched " + components.joined(separator: ", ")
			} else {
				syncProgressString = "Fetching"
			}
		}

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)
		let o = CKFetchRecordZoneChangesOptions()
		let previousToken = zoneChangeToken
		o.previousServerChangeToken = previousToken
		let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneId], optionsByRecordZoneID: [zoneId : o])
		operation.recordWithIDWasDeletedBlock = { recordId, recordType in
			if recordType == "ArchivedDropItem" {
				let itemUUID = recordId.recordName
				DispatchQueue.main.async {
					if let item = Model.item(uuid: itemUUID) {
						log("Drop \(recordType) deletion: \(itemUUID)")
						item.needsDeletion = true
						item.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
						deletionCount += 1
						updateProgress()
					}
				}
			} else if recordType == "ArchivedDropItemType" {
				let itemUUID = recordId.recordName
				DispatchQueue.main.async {
					if let component = Model.typeItem(uuid: itemUUID) {
						log("Component \(recordType) deletion: \(itemUUID)")
						component.needsDeletion = true
						component.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
						deletionCount += 1
						updateProgress()
					}
				}
			}
		}
		operation.recordChangedBlock = { record in
			let itemUUID = record.recordID.recordName

			DispatchQueue.main.async {

				if record.recordType == "ArchivedDropItem" {
					if let item = Model.item(uuid: itemUUID) {
						if record.recordChangeTag == item.cloudKitRecord?.recordChangeTag {
							log("Update but no changes to item record \(itemUUID)")
						} else {
							log("Will update existing local item for cloud record \(itemUUID)")
							item.cloudKitUpdate(from: record)
							updateCount += 1
							updateProgress()
						}
					} else {
						log("Will create new local item for cloud record \(itemUUID)")
						newDrops.append(record)
						updateProgress()
					}

				} else if record.recordType == "ArchivedDropItemType" {
					if let typeItem = Model.typeItem(uuid: itemUUID) {
						if record.recordChangeTag == typeItem.cloudKitRecord?.recordChangeTag {
							log("Update but no changes to item type data record \(itemUUID)")
						} else {
							log("Will update existing local type data: \(itemUUID)")
							typeItem.cloudKitUpdate(from: record)
							typeUpdateCount += 1
							updateProgress()
						}
					} else {
						log("Will create new local type data: \(itemUUID)")
						newTypeItemsToHookOntoDrops.append(record)
						updateProgress()
					}

				} else if itemUUID == "PositionList" {
					if record.recordChangeTag != uuidSequenceRecord?.recordChangeTag || lastSyncCompletion == .distantPast {
						log("Received an updated position list record")
						uuidSequence = (record["positionList"] as? [String]) ?? []
						updatedSequence = true
						uuidSequenceRecord = record
					} else {
						log("Received non-updated position list record")
					}
				}
			}
		}
		operation.recordZoneFetchCompletionBlock = { zoneId, token, data, moreComing, error in
			DispatchQueue.main.async {
				syncProgressString = "Applying updates"
			}
			DispatchQueue.main.async {

				if (error as? CKError)?.code == .changeTokenExpired {
					zoneChangeToken = nil
					log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
					finalCompletion(error)
					return
				}

				log("Zone \(zoneId.zoneName) changes fetch complete, processing")

				var newTypesAppended = 0
				for newTypeItemRecord in newTypeItemsToHookOntoDrops {
					if let parentId = (newTypeItemRecord["parent"] as? CKReference)?.recordID.recordName, let existingParent = Model.item(uuid: parentId) {
						let newTypeItem = ArchivedDropItemType(from: newTypeItemRecord, parentUuid: existingParent.uuid)
						existingParent.typeItems.append(newTypeItem)
						existingParent.needsReIngest = true
						newTypesAppended += 1
					}
				}
				for dropRecord in newDrops {
					createNewArchivedDrop(from: dropRecord, drawChildrenFrom: newTypeItemsToHookOntoDrops)
				}

				if updatedSequence || newDrops.count > 0 {
					let sequence = uuidSequence
					if sequence.count > 0 {
						Model.drops.sort { i1, i2 in
							let p1 = sequence.index(of: i1.uuid.uuidString) ?? -1
							let p2 = sequence.index(of: i2.uuid.uuidString) ?? -1
							return p1 < p2
						}
					}
				}

				let itemsModified = typeUpdateCount + newDrops.count + updateCount + deletionCount + newTypesAppended > 0

				if itemsModified || updatedSequence{
					NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
				}

				if itemsModified {
					// need to save stuff that's been modified
					Model.queueNextSaveCallback {
						log("Comitting zone change token")
						self.zoneChangeToken = token
					}
					Model.saveIsDueToSyncFetch = true
					Model.save()
				} else if previousToken != token {
					// it was only a position record, most likely
					if updatedSequence {
						Model.saveIndexOnly()
					}
					log("Comitting zone change token")
					self.zoneChangeToken = token
				} else {
					log("No updates available")
				}
			}
		}
		operation.fetchRecordZoneChangesCompletionBlock = { error in
			DispatchQueue.main.async {
				finalCompletion(error)
			}
		}
		go(operation)
	}

	private static func createNewArchivedDrop(from record: CKRecord, drawChildrenFrom: [CKRecord]) {
		let childrenOfThisItem = drawChildrenFrom.filter {
			if let ref = $0["parent"] as? CKReference {
				if ref.recordID == record.recordID {
					return true
				}
			}
			return false
		}
		let item = ArchivedDropItem(from: record, children: childrenOfThisItem)
		Model.drops.insert(item, at: 0)
	}

	/////////////////////////////////////////////// Whole sync

	static func sync(force: Bool = false, completion: @escaping (Error?)->Void) {

		if let l = lastiCloudAccount {
			let newToken = FileManager.default.ubiquityIdentityToken
			if !l.isEqual(newToken) {
				// shutdown
				deactivate(force: true) { _ in
					completion(nil)
				}
				if newToken == nil {
					genericAlert(title: "Sync Failure", message: "You are not logged into iCloud anymore, so sync was disabled.")
				} else {
					genericAlert(title: "Sync Failure", message: "You have changed iCloud accounts. iCloud sync was disabled to keep your data safe. You can re-activate it to upload all your data to this account as well.")
				}
				return
			}
		}

		_sync(force: force) { error in
			guard let ckError = error as? CKError else {
				completion(error)
				return
			}

			switch ckError.code {

			case .notAuthenticated,
				 .assetNotAvailable,
				 .managedAccountRestricted,
				 .missingEntitlement,
				 .zoneNotFound,
				 .incompatibleVersion,
				 .userDeletedZone,
				 .badDatabase,
				 .badContainer:

				// shutdown
				if let e = error {
					genericAlert(title: "Sync Failure", message: "There was an irrecoverable failure in sync and it has been disabled:\n\n\"\(e.finalDescription)\"")
				}
				deactivate(force: true) { _ in
					completion(nil)
				}

			case .assetFileModified,
				 .changeTokenExpired,
				 .requestRateLimited,
				 .serverResponseLost,
				 .serviceUnavailable,
				 .zoneBusy:

				let timeToRetry = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 3.0
				syncRateLimited = true
				DispatchQueue.main.asyncAfter(deadline: .now() + timeToRetry) {
					syncRateLimited = false
					_sync(force: force, completion: completion)
				}

			case .alreadyShared,
				 .assetFileNotFound,
				 .batchRequestFailed,
				 .constraintViolation,
				 .internalError,
				 .invalidArguments,
				 .limitExceeded,
				 .permissionFailure,
				 .participantMayNeedVerification,
				 .quotaExceeded,
				 .referenceViolation,
				 .serverRejectedRequest,
				 .tooManyParticipants,
				 .operationCancelled,
				 .resultsTruncated,
				 .unknownItem,
				 .serverRecordChanged,
				 .networkFailure,
				 .networkUnavailable,
				 .partialFailure:

				// regular failure
				completion(error)
			}
		}
	}

	static private func _sync(force: Bool, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { completion(nil); return }

		if syncing && !force {
			syncDirty = true
			completion(nil)
			return
		}

		syncing = true
		syncDirty = false

		func done(_ error: Error?) {
			syncing = false
			if let e = error {
				log("Sync failure: \(e.finalDescription)")
			}
			completion(error)
		}

		sendUpdatesUp { error in
			if let error = error {
				done(error)
				return
			}

			fetchDatabaseChanges { error in
				if let error = error {
					done(error)
				} else if syncDirty {
					_sync(force: true, completion: completion)
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}
}
