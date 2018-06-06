//
//  CloudManager+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CloudKit
#if os(iOS)
import UIKit
#else
import Cocoa
#endif

extension CloudManager {

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

	static func activate(completion: @escaping (Error?)->Void) {

		if syncSwitchedOn {
			completion(nil)
			return
		}

		syncTransitioning = true
		container.accountStatus { status, error in
			DispatchQueue.main.async {
				switch status {
				case .available:
					log("User has iCloud, can activate cloud sync")
					proceedWithActivation { error in
						completion(error)
						syncTransitioning = false
					}
				case .couldNotDetermine:
					activationFailure(error: error, reason: "There was an error while trying to retrieve your account status.", completion: completion)
				case .noAccount:
					activationFailure(error: error, reason: "You are not logged into iCloud on this device.", completion: completion)
				case .restricted:
					activationFailure(error: error, reason: "iCloud access is restricted on this device due to policy or parental controls.", completion: completion)
				}
			}
		}
	}

	static private func activationFailure(error: Error?, reason: String, completion: (Error?)->Void) {
		syncTransitioning = false
		log("Activation failure, reason: \(reason)")
		if let error = error {
			completion(error)
		} else {
			completion(NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: reason]))
		}
	}

	static func deactivate(force: Bool, completion: @escaping (Error?)->Void) {
		syncTransitioning = true

		let ss = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [sharedDatabaseSubscriptionId])

		let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [privateDatabaseSubscriptionId])
		ms.addDependency(ss)
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
					#if MAINAPP
					shareActionIsActioningIds = []
					#endif
					syncSwitchedOn = false
					lastiCloudAccount = nil
					#if os(iOS)
					UIApplication.shared.unregisterForRemoteNotifications()
					#else
					NSApplication.shared.unregisterForRemoteNotifications()
					#endif
					for item in Model.drops {
						item.removeFromCloudkit()
					}
					Model.save()
					log("Cloud sync deactivation complete")
					completion(nil)
				}
				syncTransitioning = false
			}
		}

		goShared(ss)
		go(ms)
	}

	static func checkMigrations() {
		if syncSwitchedOn && !migratedSharing && !syncTransitioning {
			let subscribe = subscribeToDatabaseOperation(id: sharedDatabaseSubscriptionId)
			subscribe.modifySubscriptionsCompletionBlock = { _, _, error in
				if error == nil {
					migratedSharing = true
				}
			}
			goShared(subscribe)
		}
	}

	private static func subscribeToDatabaseOperation(id: String) -> CKModifySubscriptionsOperation {
		let notificationInfo = CKNotificationInfo()
		notificationInfo.shouldSendContentAvailable = true
		notificationInfo.shouldBadge = true

		let subscription = CKDatabaseSubscription(subscriptionID: id)
		subscription.notificationInfo = notificationInfo
		return CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
	}

	private static func proceedWithActivation(completion: @escaping (Error?)->Void) {

		#if os(iOS)
		UIApplication.shared.registerForRemoteNotifications()
		#else
		NSApplication.shared.registerForRemoteNotifications(matching: [])
		#endif

		let zone = CKRecordZone(zoneName: "archivedDropItems")
		let createZone = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)

		let subscribeToPrivateDatabase = subscribeToDatabaseOperation(id: privateDatabaseSubscriptionId)
		subscribeToPrivateDatabase.addDependency(createZone)

		let subscribeToSharedDatabase = subscribeToDatabaseOperation(id: sharedDatabaseSubscriptionId)
		subscribeToSharedDatabase.addDependency(createZone)

		let positionListId = CKRecordID(recordName: "PositionList", zoneID: zone.zoneID)
		let fetchInitialUUIDSequence = CKFetchRecordsOperation(recordIDs: [positionListId])
		fetchInitialUUIDSequence.addDependency(subscribeToPrivateDatabase)
		fetchInitialUUIDSequence.addDependency(subscribeToSharedDatabase)
		fetchInitialUUIDSequence.fetchRecordsCompletionBlock = { ids2records, error in
			DispatchQueue.main.async {
				if let error = error, (error as? CKError)?.code != CKError.partialFailure {
					log("Error while activating: \(error.finalDescription)")
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
					migratedSharing = true
					lastiCloudAccount = FileManager.default.ubiquityIdentityToken
					sync(force: true, overridingWiFiPreference: true, completion: completion)
				}
			}
		}

		go(createZone)
		go(subscribeToPrivateDatabase)
		goShared(subscribeToSharedDatabase)
		go(fetchInitialUUIDSequence)
	}

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

	static func fetchDatabaseChanges(finalCompletion: @escaping (Error?)->Void) {

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
					let sequence = uuidSequence.compactMap { UUID(uuidString: $0) }
					if sequence.count > 0 {
						Model.drops.sort { i1, i2 in
							let p1 = sequence.index(of: i1.uuid) ?? -1
							let p2 = sequence.index(of: i2.uuid) ?? -1
							return p1 < p2
						}
					}
				}

				let itemsModified = typeUpdateCount + newDrops.count + updateCount + deletionCount + newTypesAppended > 0

				if itemsModified || updatedSequence{
					log("Posting external data update notification")
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

		_sync(force: force, overridingWiFiPreference: overridingWiFiPreference) { error in
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
}
