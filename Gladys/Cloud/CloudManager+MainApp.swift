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

	static func received(notificationInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		UIApplication.shared.applicationIconBadgeNumber = 0
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			if UIApplication.shared.applicationState == .background {
				Model.reloadDataIfNeeded()
			}
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
					shareActionIsActioningIds = []
					syncSwitchedOn = false
					lastiCloudAccount = nil
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
					// it was only a position record
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

	////////////////////////////////////////////////

	static func opportunisticSyncIfNeeded(isStartup: Bool) {
		if syncSwitchedOn && !syncing && (isStartup || UIApplication.shared.backgroundRefreshStatus != .available || lastSyncCompletion.timeIntervalSinceNow < -60) {
			// If there is no background fetch enabled, or it is, but we were in the background and we haven't heard from the server in a while
			sync { error in
				if let error = error {
					log("Error in foregrounding sync: \(error.finalDescription)")
				}
			}
		}
	}

	/////////////////////////////////////////////// Whole sync

	static func sync(force: Bool = false, overridingWiFiPreference: Bool = false, completion: @escaping (Error?)->Void) {

		if let l = lastiCloudAccount {
			let newToken = FileManager.default.ubiquityIdentityToken
			if !l.isEqual(newToken) {
				// shutdown
				deactivate(force: true) { _ in
					completion(nil)
				}
				if newToken == nil {
					genericAlert(title: "Sync Failure", message: "You are not logged into iCloud anymore, so sync was disabled.", on: ViewController.shared)
				} else {
					genericAlert(title: "Sync Failure", message: "You have changed iCloud accounts. iCloud sync was disabled to keep your data safe. You can re-activate it to upload all your data to this account as well.", on: ViewController.shared)
				}
				return
			}
		}

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
				if let e = error {
					genericAlert(title: "Sync Failure", message: "There was an irrecoverable failure in sync and it has been disabled:\n\n\"\(e.finalDescription)\"", on: ViewController.shared)
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
				log("Sync failure: \(e.finalDescription)")
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
