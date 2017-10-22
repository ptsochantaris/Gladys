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
		//operation.qualityOfService = .userInitiated
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

	private static var stateDirty = false
	static var pullAndPushing = false

	static func received(notificationInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			pullAndPush { error in
				if error != nil {
					completionHandler(.failed)
				} else {
					completionHandler(.newData)
				}
			}
		}
	}

	static func pullAndPush(completion: @escaping (Error?)->Void) {
		if !CloudManager.syncSwitchedOn { completion(nil); return }
		
		if pullAndPushing {
			stateDirty = true
			return
		}

		pullAndPushing = true
		stateDirty = false

		CloudManager.fetchDatabaseChanges { error in
			if let error = error {
				log("Could not perform pull: \(error.localizedDescription)")
				pullAndPushing = false
				completion(error)
			} else {
				CloudManager.sendUpdatesUp { changes, error in
					if let error = error {
						log("Could not perform push: \(error.localizedDescription)")
						pullAndPushing = false
						completion(error)
					} else {
						if stateDirty {
							pullAndPush(completion: completion)
						} else {
							pullAndPushing = false
							completion(nil)
						}
					}
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

	static func sendUpdatesUp(completion: @escaping (Bool, Error?)->Void) {
		if !syncSwitchedOn { return }

		var recordsToPush = [CKRecord]()
		for item in ViewController.shared.model.drops {
			if let itemRecord = item.populatedCloudKitRecord, !deletionQueue.contains(item.uuid.uuidString) {
				if itemRecord.recordChangeTag == nil {
					for type in item.typeItems {
						recordsToPush.append(type.newCloudKitRecord)
					}
				}
				recordsToPush.append(itemRecord)
			}
		}

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)
		let recordsToDelete = deletionQueue.map { CKRecordID(recordName: $0, zoneID: zoneId) }

		if recordsToPush.count == 0 && recordsToDelete.count == 0 {
			log("No further changes to push up")
			completion(false, nil)
			return
		} else {
			log("Pushing up \(recordsToPush.count) changes and \(recordsToDelete.count) deletions")
		}

		let operation = CKModifyRecordsOperation(recordsToSave: recordsToPush, recordIDsToDelete: recordsToDelete)
		var changes = false
		operation.perRecordCompletionBlock = { record, error in
			let itemUUID = record.recordID.recordName
			DispatchQueue.main.async {
				if let error = error {
					log("Error updating cloud record for item \(itemUUID): \(error.localizedDescription)")
				} else if let item = ViewController.shared.model.drops.first(where: { $0.uuid.uuidString == itemUUID }) {
					item.needsCloudPush = false
					item.cloudKitRecord = record
					changes = true
					log("Updated cloud record \(itemUUID)")
				} else if deletionQueue.contains(itemUUID) {
					deletionQueue.remove(itemUUID)
					changes = true
					log("Deleted cloud record \(itemUUID)")
				}
			}
		}
		operation.modifyRecordsCompletionBlock = { updatedRecords, deletedIds, error in
			DispatchQueue.main.async {
				if error == nil {
					for r in recordsToDelete {
						deletionQueue.remove(r.recordName)
					}
				}
				completion(changes, error)
			}
		}
		go(operation)
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
