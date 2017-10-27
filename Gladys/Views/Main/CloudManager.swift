//
//  CloudManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 21/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CloudKit

final class CloudManager {

	private static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

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
					zoneChangeTokens = [:]
					lastSyncCompletion = .distantPast
					uuidSequence = nil
					uuidSequenceRecord = nil
					dbChangeToken = nil
					syncSwitchedOn = false
					UIApplication.shared.unregisterForRemoteNotifications()
					for item in ViewController.shared.model.drops {
						item.cloudKitRecord = nil
						for typeItem in item.typeItems {
							typeItem.cloudKitRecord = nil
						}
					}
					ViewController.shared.model.save()
					log("Cloud sync deactivation complete")
					completion(nil)
				}
				syncTransitioning = false
			}
		}
		go(ms)
	}

	private static func proceedWithActivation(completion: @escaping (Error?)->Void) {

		UIApplication.shared.registerForRemoteNotifications()

		let notificationInfo = CKNotificationInfo()
		notificationInfo.shouldSendContentAvailable = true

		let subscription = CKDatabaseSubscription(subscriptionID: "private-changes")
		subscription.notificationInfo = notificationInfo

		let zone = CKRecordZone(zoneName: "archivedDropItems")
		let createZone = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
		createZone.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
			if let error = error {
				log("Error while creating zone: \(error.localizedDescription)")
				DispatchQueue.main.async {
					completion(error)
				}
			}
		}

		let subscribeToZone = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
		subscribeToZone.addDependency(createZone)
		subscribeToZone.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			DispatchQueue.main.async {
				if let error = error {
					completion(error)
				} else {
					syncSwitchedOn = true
					sync(force: true, overridingWiFiPreference: true, completion: completion)
				}
			}
		}

		go(createZone)
		go(subscribeToZone)
	}

	private static func go(_ operation: CKDatabaseOperation) {
		container.privateCloudDatabase.add(operation)
	}

	private static func fetchZoneChanges(ids: [CKRecordZoneID], finalCompletion: @escaping (Error?)->Void) {

		guard ids.count > 0 else {
			log("No zone changes, hence no record changes")
			DispatchQueue.main.async {
				finalCompletion(nil)
			}
			return
		}

		var lookup = zoneChangeTokens
		var itemFieldsWereModified = false
		var itemsNeedDeletion = false
		var updatedSequence = false
		var newDrops = [CKRecord]()
		var newTypeItemsToHookOntoDrops = [CKRecord]()

		let changeTokenOptionsList = ids.map { zoneId -> (CKRecordZoneID, CKFetchRecordZoneChangesOptions) in
			let o = CKFetchRecordZoneChangesOptions()
			if let changeToken = lookup[zoneId] {
				o.previousServerChangeToken = changeToken
			}
			return (zoneId, o)
		}
		let d = Dictionary<CKRecordZoneID, CKFetchRecordZoneChangesOptions>(uniqueKeysWithValues: changeTokenOptionsList)
		let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: ids, optionsByRecordZoneID: d)
		operation.recordWithIDWasDeletedBlock = { recordId, recordType in
			if recordType != "ArchivedDropItem" { return }
			let itemUUID = recordId.recordName
			DispatchQueue.main.async {
				log("Record \(recordType) deletion: \(itemUUID)")
				if let item = ViewController.shared.model.item(uuid: itemUUID) {
					item.needsDeletion = true
					itemsNeedDeletion = true
				}
			}
		}
		operation.recordChangedBlock = { record in
			DispatchQueue.main.async {
				if record.recordType == "ArchivedDropItem" {
					let itemUUID = record.recordID.recordName
					if let item = ViewController.shared.model.item(uuid: itemUUID) {
						if record.recordChangeTag == item.cloudKitRecord?.recordChangeTag {
							log("Update but no changes to item record \(itemUUID)")
						} else {
							log("Will update existing local item for cloud record \(itemUUID)")
							item.cloudKitUpdate(from: record)
							itemFieldsWereModified = true
						}
					} else {
						log("Will create new local item for cloud record \(itemUUID)")
						newDrops.append(record)
						itemFieldsWereModified = true
					}
				} else if record.recordType == "ArchivedDropItemType" {
					let itemUUID = record.recordID.recordName
					if let typeItem = ViewController.shared.model.typeItem(uuid: itemUUID) {
						if record.recordChangeTag == typeItem.cloudKitRecord?.recordChangeTag {
							log("Update but no changes to item type record \(itemUUID)")
						} else {
							log("Will update existing local type data: \(itemUUID)")
							typeItem.cloudKitUpdate(from: record)
							itemFieldsWereModified = true
						}
					} else {
						log("Will create new local type data: \(itemUUID)")
						newTypeItemsToHookOntoDrops.append(record)
					}
				} else if record.recordType == "PositionList" {
					if record.recordChangeTag != uuidSequenceRecord?.recordChangeTag {
						log("Received an updated position list record")
						uuidSequence = record["positionList"] as? [String]
						updatedSequence = true
						itemFieldsWereModified = true
						uuidSequenceRecord = record
					} else {
						log("Received non-updated position list record")
					}
				}
			}
		}
		operation.recordZoneFetchCompletionBlock = { zoneId, token, data, moreComing, error in
			if (error as? CKError)?.code == .changeTokenExpired {
				lookup[zoneId] = nil
				log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
			} else {
				lookup[zoneId] = token
				log("Zone \(zoneId.zoneName) changes fetch complete")
			}
		}
		operation.fetchRecordZoneChangesCompletionBlock = { error in
			DispatchQueue.main.async {
				if itemFieldsWereModified {
					// ingestions will take care of save
					for dropRecord in newDrops {
						createNewArchivedDrop(from: dropRecord, drawChildrenFrom: newTypeItemsToHookOntoDrops)
					}
					if updatedSequence {
						NotificationCenter.default.post(name: .CloudManagerUpdatedUUIDSequence, object: nil)
					} else {
						NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
					}
				} else if itemsNeedDeletion {
					// deletions will take care of save
					NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
				}
				if let error = error {
					finalCompletion(error)
				} else {
					log("Received record changes")
					self.zoneChangeTokens = lookup
					finalCompletion(nil)
				}
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
		ViewController.shared.model.drops.insert(item, at: 0)
	}

	private static func fetchDatabaseChanges(finalCompletion: @escaping (Error?)->Void) {
		var changedZoneIds = [CKRecordZoneID]()

		let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: dbChangeToken)
		operation.recordZoneWithIDChangedBlock = { zoneId in
			changedZoneIds.append(zoneId)
		}
		operation.fetchDatabaseChangesCompletionBlock = { serverChangeToken, moreComing, error in
			if let error = error {
				if (error as? CKError)?.code == .changeTokenExpired {
					dbChangeToken = nil
					log("Zone log could not be retrieved because token was stale, will retry")
				}
				DispatchQueue.main.async {
					finalCompletion(error)
				}
			} else {
				log("Received zone log, \(changedZoneIds.count) zones have changes")
				dbChangeToken = serverChangeToken
				fetchZoneChanges(ids: changedZoneIds, finalCompletion: finalCompletion)
			}
		}
		go(operation)
	}

	private static var syncDirty = false
	private static var syncForceOrderSend = false

	private static let agoFormatter: DateComponentsFormatter = {
		let f = DateComponentsFormatter()
		f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
		f.unitsStyle = .abbreviated
		f.maximumUnitCount = 2
		return f
	}()
	static var syncString: String {
		if syncing {
			return "Syncing"
		}

		let i = -lastSyncCompletion.timeIntervalSinceNow
		if i < 1.0 {
			return "Synced"
		} else if lastSyncCompletion != .distantPast, let s = agoFormatter.string(from: i) {
			return "Synced \(s) ago"
		} else {
			return "Never"
		}
	}

	static func received(notificationInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			sync { error in
				if error != nil {
					completionHandler(.failed)
				} else {
					completionHandler(.newData)
				}
			}
		}
	}

	static func sync(force: Bool = false, overridingWiFiPreference: Bool = false, completion: @escaping (Error?)->Void) {
		_sync(force: force, overridingWiFiPreference: overridingWiFiPreference) { error in
			guard let ckError = error as? CKError else {
				completion(error)
				return
			}

			switch ckError.code {

			case .notAuthenticated,
			     .managedAccountRestricted,
			     .missingEntitlement,
			     .zoneNotFound,
			     .incompatibleVersion,
			     .userDeletedZone,
			     .badDatabase,
			     .badContainer:

				// shutdown
				deactivate(force: true) { _ in
					completion(error)
					if let e = error {
						genericAlert(title: "Sync Failure", message: "There was an irrecoverable failure in sync and it has been disabled:\n\n\"\(e.localizedDescription)\"", on: ViewController.shared)
					}
				}

			case .assetFileModified,
			     .changeTokenExpired,
			     .requestRateLimited,
			     .serverResponseLost,
			     .serviceUnavailable,
			     .zoneBusy:

				let timeToRetry = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 3.0
				DispatchQueue.main.asyncAfter(deadline: .now() + timeToRetry) {
					_sync(force: force, overridingWiFiPreference: overridingWiFiPreference, completion: completion)
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

	static private func _sync(force: Bool, overridingWiFiPreference: Bool, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn {
			completion(nil)
			return
		}

		if !force && !overridingWiFiPreference && onlySyncOverWiFi && reachability.status != .ReachableViaWiFi {
			log("Skipping sync because no WiFi is present and user has selected WiFi sync only")
			completion(nil)
			return
		}

		if syncing && !force {
			syncDirty = true
			completion(nil)
			return
		}

		let bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.syncTask", expirationHandler: nil)

		syncing = true
		syncDirty = false

		func endBgTask() {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				UIApplication.shared.endBackgroundTask(bgTask)
			}
		}

		sendUpdatesUp { error in
			if let error = error {
				log("Could not perform push: \(error.localizedDescription)")
				syncing = false
				completion(error)
				endBgTask()
			} else {
				fetchDatabaseChanges { error in
					if let error = error {
						log("Could not perform pull: \(error.localizedDescription)")
						syncing = false
						completion(error)
					} else if syncDirty {
						sync(force: true, completion: completion)
					} else {
						syncing = false
						completion(nil)
						lastSyncCompletion = Date()
					}
					endBgTask()
				}
			}
		}
	}

	/////////////////////////////////////////////

	static var syncTransitioning = false {
		didSet {
			if syncTransitioning != oldValue {
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
				UIApplication.shared.isNetworkActivityIndicatorVisible = syncing || syncTransitioning
			}
		}
	}

	static var syncing = false {
		didSet {
			if syncing != oldValue {
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
				UIApplication.shared.isNetworkActivityIndicatorVisible = syncing || syncTransitioning
			}
		}
	}

	static var lastSyncCompletion: Date {
		get {
			return UserDefaults.standard.object(forKey: "lastSyncCompletion") as? Date ?? .distantPast
		}

		set {
			let d = UserDefaults.standard
			d.set(newValue, forKey: "lastSyncCompletion")
			d.synchronize()
		}
	}

	static var syncSwitchedOn: Bool {
		get {
			return UserDefaults.standard.bool(forKey: "syncSwitchedOn")
		}

		set {
			let d = UserDefaults.standard
			d.set(newValue, forKey: "syncSwitchedOn")
			d.synchronize()
		}
	}

	static var onlySyncOverWiFi: Bool {
		get {
			return UserDefaults.standard.bool(forKey: "onlySyncOverWiFi")
		}

		set {
			let d = UserDefaults.standard
			d.set(newValue, forKey: "onlySyncOverWiFi")
			d.synchronize()
		}
	}

	private static var dbChangeToken: CKServerChangeToken? {
		get {
			if let d = UserDefaults.standard.data(forKey: "dbChangeToken") {
				return NSKeyedUnarchiver.unarchiveObject(with: d) as? CKServerChangeToken
			} else {
				return nil
			}
		}
		set {
			let d = UserDefaults.standard
			if let n = newValue {
				let data = NSKeyedArchiver.archivedData(withRootObject: n)
				d.set(data, forKey: "dbChangeToken")
			} else {
				d.removeObject(forKey: "dbChangeToken")
			}
			d.synchronize()
		}
	}

	private static var zoneChangeTokens: [CKRecordZoneID: CKServerChangeToken] {
		get {
			if let d = UserDefaults.standard.data(forKey: "zoneChangeTokens") {
				return NSKeyedUnarchiver.unarchiveObject(with: d) as? [CKRecordZoneID: CKServerChangeToken] ?? [:]
			} else {
				return [:]
			}
		}
		set {
			let d = UserDefaults.standard
			let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
			d.set(data, forKey: "zoneChangeTokens")
			d.synchronize()
		}
	}

	///////////////////////////////////////

	static var uuidSequence: [String]? {
		get {
			if let d = UserDefaults.standard.data(forKey: "uuidSequence") {
				return NSKeyedUnarchiver.unarchiveObject(with: d) as? [String]
			} else {
				return nil
			}
		}
		set {
			let d = UserDefaults.standard
			if let n = newValue {
				let data = NSKeyedArchiver.archivedData(withRootObject: n)
				d.set(data, forKey: "uuidSequence")
			} else {
				d.removeObject(forKey: "uuidSequence")
			}
			d.synchronize()
		}
	}

	private static var uuidSequenceRecordPath: URL {
		return Model.appStorageUrl.appendingPathComponent("ck-uuid-sequence", isDirectory: false)
	}

	private static var uuidSequenceRecord: CKRecord? {
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

	private static var deleteQueuePath: URL {
		return Model.appStorageUrl.appendingPathComponent("ck-delete-queue", isDirectory: false)
	}

	private static var deletionQueue: Set<String> {
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

	private static func sendUpdatesUp(completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { return }

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

		var idsToPush = [String]()
		var payloadsToPush = ViewController.shared.model.drops.flatMap { item -> [CKRecord]? in
			if let itemRecord = item.populatedCloudKitRecord {
				var payload = item.typeItems.flatMap { $0.populatedCloudKitRecord }
				payload.append(itemRecord)
				idsToPush.append(item.uuid.uuidString)
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

		let currentUUIDSequence = ViewController.shared.model.drops.map { $0.uuid.uuidString }
		if syncForceOrderSend || (uuidSequence ?? []) != currentUUIDSequence {
			let record = uuidSequenceRecord ?? CKRecord(recordType: "PositionList", recordID: CKRecordID(recordName: "PositionList", zoneID: zoneId))
			record["positionList"] = currentUUIDSequence as NSArray
			payloadsToPush.append([record])
		}

		let recordsToDelete = deletionIdsSnapshot.map { CKRecordID(recordName: $0, zoneID: zoneId) }.bunch(maxSize: 100)

		if payloadsToPush.count == 0 && recordsToDelete.count == 0 {
			log("No further changes to push up")
			completion(nil)
			return
		}

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
						log("Error deleting items: \(error.localizedDescription)")
					}
					for uuid in (deletedRecordIds?.map({ $0.recordName })) ?? [] {
						if deletionIdsSnapshot.contains(uuid) {
							deletionQueue.remove(uuid)
							log("Deleted cloud record \(uuid)")
						}
					}
				}
			}
			operations.append(operation)
		}

		log("Pushing up \(payloadsToPush.count) item blocks")

		for recordList in payloadsToPush {
			let operation = CKModifyRecordsOperation(recordsToSave: recordList, recordIDsToDelete: nil)
			operation.savePolicy = .allKeys
			operation.isAtomic = true
			operation.modifyRecordsCompletionBlock = { updatedRecords, deletedRecordIds, error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error updating cloud records: \(error.localizedDescription)")
						latestError = error
					}
					for record in updatedRecords ?? [] {
						let itemUUID = record.recordID.recordName
						if itemUUID == "PositionList" {
							uuidSequence = currentUUIDSequence
							syncForceOrderSend = false
							uuidSequenceRecord = record
							log("Sent updated \(record.recordType) cloud record")
						} else if let item = ViewController.shared.model.item(uuid: itemUUID) {
							item.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
						} else if let typeItem = ViewController.shared.model.typeItem(uuid: itemUUID) {
							typeItem.cloudKitRecord = record
							log("Sent updated \(record.recordType) cloud record \(itemUUID)")
						}
					}
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
	}

	///////////////////////////////////

	static func tryManualSync(from vc: UIViewController) {
		if reachability.status == .NotReachable {
			genericAlert(title: "Network Not Available", message: "Please check your network connection", on: vc)
			return
		}

		CloudManager.sync(overridingWiFiPreference: true) { error in
			if let error = error {
				genericAlert(title: "Sync Error", message: error.localizedDescription, on: vc)
			}
		}
	}

	///////////////////////////////////

	static let statusListener = CloudStatusListener()
	
	final class CloudStatusListener {

		private var holdOffOnSyncWhileWeInvestigateICloudStatus = false

		func start() {
			NotificationCenter.default.addObserver(self, selector: #selector(iCloudStatusChanged(_:)), name: .CKAccountChanged, object: nil)
			NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: .UIApplicationWillEnterForeground, object: nil)
		}

		@objc private func iCloudStatusChanged(_ notification: Notification) {
			if !CloudManager.syncSwitchedOn { return }

			holdOffOnSyncWhileWeInvestigateICloudStatus = true
			container.accountStatus { status, error in
				if status == .available {
					DispatchQueue.main.async {
						self.holdOffOnSyncWhileWeInvestigateICloudStatus = false
						self.proceedWithSync()
					}
				} else {
					log("iCloud deactivated on this device, shutting down sync")
					DispatchQueue.main.async {
						deactivate(force: true) { _ in
							self.holdOffOnSyncWhileWeInvestigateICloudStatus = false
							genericAlert(title: "Sync Disabled", message: "Syncing has been disabled as you are no longer logged into iCloud on this device.", on: ViewController.shared)
						}
					}
				}
			}
		}

		@objc private func willEnterForeground(_ notification: Notification) {
			if !CloudManager.syncSwitchedOn { return }

			if holdOffOnSyncWhileWeInvestigateICloudStatus {
				return
			}
			proceedWithSync()
		}

		private func proceedWithSync() {
			CloudManager.sync { error in
				if let error = error {
					log("Error in foregrounding sync: \(error.localizedDescription)")
				}
			}
		}

		deinit {
			NotificationCenter.default.removeObserver(self)
		}
	}
}
