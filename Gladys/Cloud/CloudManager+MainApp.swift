//
//  CloudManager+MainApp.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit
import UIKit

extension CloudManager {

	//////////////////////////////////////////////// UI
	
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

	/////////////////////////////////////////////////// Push

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
					zoneChangeMayNotReflectSavedChanges = false
					syncSwitchedOn = false
					UIApplication.shared.unregisterForRemoteNotifications()
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
			if let error = error {
				log("Error while updating zone subscription: \(error.localizedDescription)")
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
					log("Error while fetching inital item sequence: \(error.localizedDescription)")
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
					sync(force: true, overridingWiFiPreference: true, completion: completion)
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
				log("Error while deleting zone: \(error.localizedDescription)")
			}
			DispatchQueue.main.async {
				completion(error)
			}
		}
		go(deleteZone)
	}

	/////////////////////////////////////////// Fetching

	private static func fetchDatabaseChanges(finalCompletion: @escaping (Error?)->Void) {

		var itemsModified = false
		var updatedSequence = false
		var newDrops = [CKRecord]()
		var newTypeItemsToHookOntoDrops = [CKRecord]()

		let o = CKFetchRecordZoneChangesOptions()
		if zoneChangeMayNotReflectSavedChanges {
			log("Change token could be unreliable, performing full fetch")
		} else {
			log("Performing delta fetch")
			o.previousServerChangeToken = zoneChangeMayNotReflectSavedChanges ? nil : zoneChangeToken
		}

		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)
		let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneId], optionsByRecordZoneID: [zoneId : o])
		operation.recordWithIDWasDeletedBlock = { recordId, recordType in
			if recordType != "ArchivedDropItem" { return }
			let itemUUID = recordId.recordName
			log("Record \(recordType) deletion: \(itemUUID)")
			DispatchQueue.main.async {
				if let item = Model.item(uuid: itemUUID) {
					item.needsDeletion = true
					zoneChangeMayNotReflectSavedChanges = true
					itemsModified = true
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
							zoneChangeMayNotReflectSavedChanges = true
							itemsModified = true
						}
					} else {
						log("Will create new local item for cloud record \(itemUUID)")
						newDrops.append(record)
						zoneChangeMayNotReflectSavedChanges = true
						itemsModified = true
					}

				} else if record.recordType == "ArchivedDropItemType" {
					if let typeItem = Model.typeItem(uuid: itemUUID) {
						if record.recordChangeTag == typeItem.cloudKitRecord?.recordChangeTag {
							log("Update but no changes to item type record \(itemUUID)")
						} else {
							log("Will update existing local type data: \(itemUUID)")
							typeItem.cloudKitUpdate(from: record)
							itemsModified = true
							zoneChangeMayNotReflectSavedChanges = true
						}
					} else {
						log("Will create new local type data: \(itemUUID)")
						newTypeItemsToHookOntoDrops.append(record)
					}

				} else if itemUUID == "PositionList" {
					if record.recordChangeTag != uuidSequenceRecord?.recordChangeTag || lastSyncCompletion == .distantPast {
						log("Received an updated position list record")
						uuidSequence = (record["positionList"] as? [String]) ?? []
						updatedSequence = true
						itemsModified = true
						zoneChangeMayNotReflectSavedChanges = true
						uuidSequenceRecord = record
					} else {
						log("Received non-updated position list record")
					}
				}
			}
		}
		operation.recordZoneFetchCompletionBlock = { zoneId, token, data, moreComing, error in
			DispatchQueue.main.async {

				if (error as? CKError)?.code == .changeTokenExpired {
					zoneChangeToken = nil
					zoneChangeMayNotReflectSavedChanges = false
					log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
					finalCompletion(error)
					return
				}

				if itemsModified || zoneChangeMayNotReflectSavedChanges {
					zoneChangeMayNotReflectSavedChanges = true
					Model.queueNextSaveCallback {
						zoneChangeMayNotReflectSavedChanges = false
						log("Commited zone change token")
					}
				}
				zoneChangeToken = token
				log("Zone \(zoneId.zoneName) changes fetch complete")

				if itemsModified {
					// ingestions and deletions will take care of save
					for dropRecord in newDrops {
						createNewArchivedDrop(from: dropRecord, drawChildrenFrom: newTypeItemsToHookOntoDrops)
					}
					if updatedSequence {
						NotificationCenter.default.post(name: .CloudManagerUpdatedUUIDSequence, object: nil)
					}
					NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
				}

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

	/////////////////////////////////// Helpers

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

	/////////////////////////////////// Status

	private static var holdOffOnSyncWhileWeInvestigateICloudStatus = false

	static func listenForAccountChanges() {
		let n = NotificationCenter.default

		n.addObserver(forName: .CKAccountChanged, object: nil, queue: OperationQueue.main) { _ in
			if !syncSwitchedOn { return }

			holdOffOnSyncWhileWeInvestigateICloudStatus = true
			container.accountStatus { status, error in
				if status == .available || status == .couldNotDetermine {
					DispatchQueue.main.async {
						holdOffOnSyncWhileWeInvestigateICloudStatus = false
						proceedWithForegroundingSync()
					}
				} else {
					log("iCloud deactivated on this device, shutting down sync")
					DispatchQueue.main.async {
						deactivate(force: true) { _ in
							holdOffOnSyncWhileWeInvestigateICloudStatus = false
							genericAlert(title: "Sync Disabled", message: "Syncing has been disabled as you are no longer logged into iCloud on this device.", on: ViewController.shared)
						}
					}
				}
			}
		}

		n.addObserver(forName: .UIApplicationWillEnterForeground, object: nil, queue: OperationQueue.main) { _ in
			if !syncSwitchedOn || holdOffOnSyncWhileWeInvestigateICloudStatus { return }
			proceedWithForegroundingSync()
		}
	}

	private static func proceedWithForegroundingSync() {
		CloudManager.sync { error in
			if let error = error {
				log("Error in foregrounding sync: \(error.localizedDescription)")
			}
		}
	}

	/////////////////////////////////////////////// Whole sync

	static func sync(force: Bool = false, overridingWiFiPreference: Bool = false, completion: @escaping (Error?)->Void) {
		_sync(force: force, overridingWiFiPreference: overridingWiFiPreference, existingBgTask: nil) { error in
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
					_sync(force: force, overridingWiFiPreference: overridingWiFiPreference, existingBgTask: nil, completion: completion)
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

	static private func _sync(force: Bool, overridingWiFiPreference: Bool, existingBgTask: UIBackgroundTaskIdentifier?, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { completion(nil); return }

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

		let bgTask: UIBackgroundTaskIdentifier
		if let e = existingBgTask {
			bgTask = e
		} else {
			log("Starting cloud sync background task")
			bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.syncTask", expirationHandler: nil)
		}

		syncing = true
		syncDirty = false

		func done(_ error: Error?) {
			syncing = false
			if let e = error {
				log("Sync failure: \(e.localizedDescription)")
			}
			completion(error)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				log("Ending cloud sync background task")
				UIApplication.shared.endBackgroundTask(bgTask)
			}
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
					_sync(force: true, overridingWiFiPreference:overridingWiFiPreference, existingBgTask: bgTask, completion: completion)
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}
}
