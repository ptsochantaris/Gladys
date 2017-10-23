//
//  CloudManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 21/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CloudKit

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

	static func deactivate(completion: @escaping (Error?)->Void) {
		syncTransitioning = true
		let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: ["private-changes"])
		ms.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			DispatchQueue.main.async {
				if let error = error {
					log("Cloud sync deactivation failed")
					completion(error)
				} else {
					deletionQueue.removeAll()
					zoneChangeTokens = [:]
					dbChangeToken = nil
					syncSwitchedOn = false
					UIApplication.shared.unregisterForRemoteNotifications()
					for item in ViewController.shared.model.drops {
						item.cloudKitRecord = nil
						item.needsCloudPush = false
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

		let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
		operation.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				DispatchQueue.main.async {
					completion(error)
				}
			} else {
				fetchDatabaseChanges { error in
					if let error = error {
						DispatchQueue.main.async {
							completion(error)
						}
					} else {
						syncSwitchedOn = true
						completion(nil)
					}
				}
			}
		}
		go(operation)
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
		var changes = false
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
				log("Record \(recordType) deleted: \(itemUUID)")
				if let item = ViewController.shared.model.drops.first(where: { $0.uuid.uuidString == itemUUID }) {
					ViewController.shared.deleteRequested(for: [item])
				}
			}
		}
		operation.recordChangedBlock = { record in
			DispatchQueue.main.async {
				if record.recordType == "ArchivedDropItem" {
					let itemUUID = record.recordID.recordName
					if let item = ViewController.shared.model.drops.first(where: { $0.uuid.uuidString == itemUUID }) {
						log("Will update existing local item for cloud record \(itemUUID)")
						item.cloudKitUpdate(from: record)
					} else {
						log("Will create new local item for cloud record \(itemUUID)")
						newDrops.append(record)
					}
					changes = true
				} else if record.recordType == "ArchivedDropItemType" {
					log("Received a child item: \(record.recordID.recordName)")
					newTypeItemsToHookOntoDrops.append(record)
				}
			}
		}
		operation.recordZoneFetchCompletionBlock = { zoneId, token, data, moreComing, error in
			lookup[zoneId] = token
			log("Zone \(zoneId.zoneName) changes complete")
		}
		operation.fetchRecordZoneChangesCompletionBlock = { error in
			DispatchQueue.main.async {
				if changes {
					for dropRecord in newDrops {
						createNewArchivedDrop(from: dropRecord, drawChildrenFrom: newTypeItemsToHookOntoDrops)
					}
					if newDrops.count == 0 { // was only deletions, let's save, otherwise ingestion will cause save later on
						ViewController.shared.model.save()
					}
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

	static func received(notificationInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			sync { changes, error in
				if error != nil {
					completionHandler(.failed)
				} else {
					completionHandler(.newData)
				}
			}
		}
	}

	static func sync(force: Bool = false, onlySend: Bool = false, previouslySentChanges: Bool = false, completion: @escaping (Bool, Error?)->Void) {
		if !CloudManager.syncSwitchedOn { completion(previouslySentChanges, nil); return }
		
		if syncing && !force {
			syncDirty = true
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

		func send() {
			CloudManager.sendUpdatesUp { changes, error in
				let previousOrCurrentChanges = previouslySentChanges || changes
				if let error = error {
					log("Could not perform push: \(error.localizedDescription)")
					syncing = false
					completion(previousOrCurrentChanges, error)
					endBgTask()
				} else {
					if syncDirty {
						sync(force: true, completion: completion)
						endBgTask()
					} else {
						syncing = false
						completion(previousOrCurrentChanges, nil)
						endBgTask()
					}
				}
			}
		}

		if onlySend {
			send()
		} else {
			CloudManager.fetchDatabaseChanges { error in
				if let error = error {
					log("Could not perform pull: \(error.localizedDescription)")
					syncing = false
					completion(previouslySentChanges, error)
					endBgTask()
				} else {
					send()
				}
			}
		}
	}

	/////////////////////////////////////////////

	static var syncTransitioning = false {
		didSet {
			if syncTransitioning != oldValue {
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	static var syncing = false {
		didSet {
			if syncing != oldValue {
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
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

	private static func sendUpdatesUp(completion: @escaping (Bool, Error?)->Void) {
		if !syncSwitchedOn { return }

		var payloadsToPush = [[CKRecord]]()
		for item in ViewController.shared.model.drops {
			if let itemRecord = item.populatedCloudKitRecord, !deletionQueue.contains(item.uuid.uuidString) {
				var payload = [CKRecord]()
				if itemRecord.recordChangeTag == nil {
					for type in item.typeItems {
						payload.append(type.populatedCloudKitRecord)
					}
				}
				payload.append(itemRecord)
				payloadsToPush.append(payload)
			}
		}

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)
		let recordsToDelete = deletionQueue.map { CKRecordID(recordName: $0, zoneID: zoneId) }.bunch(maxSize: 100)

		if payloadsToPush.count == 0 && recordsToDelete.count == 0 {
			log("No further changes to push up")
			completion(false, nil)
			return
		}

		var changes = false
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
						if deletionQueue.contains(uuid) {
							deletionQueue.remove(uuid)
							log("Deleted cloud record \(uuid)")
							changes = true
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
						if let item = ViewController.shared.model.drops.first(where: { $0.uuid.uuidString == itemUUID }) {
							item.needsCloudPush = false
							item.cloudKitRecord = record
							changes = true
							log("Updated \(record.recordType) cloud record \(itemUUID)")
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
			completion(changes, latestError)
		}
		operations.forEach {
			go($0)
		}
	}

	///////////////////////////////////

	private let statusListener = CloudStatusListener()
	private class CloudStatusListener {
		init() {
			NotificationCenter.default.addObserver(self, selector: #selector(iCloudStatusChanged(_:)), name: .CKAccountChanged, object: nil)
		}
		@objc private func iCloudStatusChanged(_ notification: Notification) {
			container.accountStatus { status, error in
				if status != .available {
					log("iCloud deactivated on this device, shutting down sync")
					deactivate { _ in }
				}
			}
		}
		deinit {
			NotificationCenter.default.removeObserver(self)
		}
	}
}
