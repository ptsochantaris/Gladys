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

		var finalError: Error?

		let ss = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [sharedDatabaseSubscriptionId])
		ss.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				finalError = error
			}
		}

		let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [privateDatabaseSubscriptionId])
		ms.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				finalError = error
			}
		}

		let doneOperation = BlockOperation {
			if let finalError = finalError, !force {
				log("Cloud sync deactivation failed")
				completion(finalError)
			} else {
				deletionQueue.removeAll()
				lastSyncCompletion = .distantPast
				uuidSequence = []
				uuidSequenceRecord = nil
				PullState.wipeDatabaseTokens()
				PullState.wipeZoneTokens()
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

		doneOperation.addDependency(ss)
		goShared(ss)

		doneOperation.addDependency(ms)
		go(ms)

		OperationQueue.main.addOperation(doneOperation)
	}

	static func checkMigrations() {
		PullState.checkMigrations()
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
		createZone.modifyRecordZonesCompletionBlock = { _, _, error in
			if let error = error {
				abortActivation(error, completion: completion)
			} else {
				let subscribeToPrivateDatabase = subscribeToDatabaseOperation(id: privateDatabaseSubscriptionId)
				subscribeToPrivateDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
					if let error = error {
						abortActivation(error, completion: completion)
					} else {
						let subscribeToSharedDatabase = subscribeToDatabaseOperation(id: sharedDatabaseSubscriptionId)
						subscribeToSharedDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
							if let error = error {
								abortActivation(error, completion: completion)
							} else {
								fetchInitialUUIDSequence(zone: zone, completion: completion)
							}
						}
						goShared(subscribeToSharedDatabase)
					}
				}
				go(subscribeToPrivateDatabase)
			}
		}
		go(createZone)
	}

	static private func abortActivation(_ error: Error, completion: @escaping (Error?)->Void) {
		DispatchQueue.main.async {
			completion(error)
			deactivate(force: true, completion: { _ in })
		}
	}

	static private func fetchInitialUUIDSequence(zone: CKRecordZone, completion: @escaping (Error?)->Void) {
		let positionListId = CKRecordID(recordName: RecordType.positionList, zoneID: zone.zoneID)
		let fetchInitialUUIDSequence = CKFetchRecordsOperation(recordIDs: [positionListId])
		fetchInitialUUIDSequence.fetchRecordsCompletionBlock = { ids2records, error in
			DispatchQueue.main.async {
				if let error = error, (error as? CKError)?.code != CKError.partialFailure {
					log("Error while activating: \(error.finalDescription)")
					abortActivation(error, completion: completion)
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

		go(fetchInitialUUIDSequence)
	}

	static func eraseZoneIfNeeded(completion: @escaping (Error?)->Void) {
		showNetwork = true
		let deleteZone = CKModifyRecordZonesOperation(recordZonesToSave:nil, recordZoneIDsToDelete: [ArchivedDropItem.privateZoneId])
		deleteZone.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
			if let error = error {
				log("Error while deleting zone: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				showNetwork = false
				completion(error)
			}
		}
		go(deleteZone)
	}

	static private func recordDeleted(recordId: CKRecordID, recordType: String, stats: PullState) {
		let itemUUID = recordId.recordName
		DispatchQueue.main.async {
			switch recordType {
			case RecordType.item:
				if let item = Model.item(uuid: itemUUID) {
					log("Drop \(recordType) deletion: \(itemUUID)")
					item.needsDeletion = true
					item.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
					item.cloudKitShareRecord = nil // get rid of useless file
					stats.deletionCount += 1
				}
			case RecordType.component:
				if let component = Model.typeItem(uuid: itemUUID) {
					log("Component \(recordType) deletion: \(itemUUID)")
					component.needsDeletion = true
					component.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
					stats.deletionCount += 1
				}
			case RecordType.share:
				if let associatedItem = Model.item(shareId: itemUUID) {
					log("Share record deleted for item \(associatedItem.uuid)")
					associatedItem.cloudKitShareRecord = nil
					stats.deletionCount += 1
				}
			default:
				log("Warning: Received deletion for unknown record type: \(recordType)")
			}
		}
	}

	static private func recordChanged(record: CKRecord, stats: PullState) {
		let itemUUID = record.recordID.recordName
		let recordType = record.recordType
		DispatchQueue.main.async {
			switch recordType {
			case RecordType.item:
				if let item = Model.item(uuid: itemUUID) {
					if record.recordChangeTag == item.cloudKitRecord?.recordChangeTag {
						log("Update but no changes to item record \(itemUUID)")
					} else {
						log("Will update existing local item for cloud record \(itemUUID)")
						item.cloudKitUpdate(from: record)
						stats.updateCount += 1
					}
				} else {
					log("Will create new local item for cloud record \(itemUUID)")
					stats.newDrops.append(record)
				}
			case RecordType.component:
				if let typeItem = Model.typeItem(uuid: itemUUID) {
					if record.recordChangeTag == typeItem.cloudKitRecord?.recordChangeTag {
						log("Update but no changes to item type data record \(itemUUID)")
					} else {
						log("Will update existing local type data: \(itemUUID)")
						typeItem.cloudKitUpdate(from: record)
						stats.typeUpdateCount += 1
					}
				} else {
					log("Will create new local type data: \(itemUUID)")
					stats.newTypeItemsToHookOntoDrops.append(record)
				}
			case RecordType.positionList:
				if record.recordChangeTag != uuidSequenceRecord?.recordChangeTag || lastSyncCompletion == .distantPast {
					log("Received an updated position list record")
					uuidSequence = (record["positionList"] as? [String]) ?? []
					stats.updatedSequence = true
					uuidSequenceRecord = record
				} else {
					log("Received non-updated position list record")
				}
			case RecordType.share:
				if let share = record as? CKShare {
					if let associatedItem = Model.item(shareId: itemUUID) {
						log("Share record updated for item \(associatedItem.uuid)")
						associatedItem.cloudKitShareRecord = share
						stats.updateCount += 1
					} else {
						log("Will create new share record for \(itemUUID)")
						stats.newShareItemsToSetForDrops.append(share)
					}
				}
			default:
				log("Warning: Received record update for unkown type: \(recordType)")
			}
		}
	}

	static private func zoneFetchDone(zoneId: CKRecordZoneID, token: CKServerChangeToken?, error: Error?, stats: PullState) {
		if (error as? CKError)?.code == .changeTokenExpired {
			DispatchQueue.main.async {
				PullState.setZoneToken(nil, for: zoneId)
				syncProgressString = "Retrying"
				log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
			}
		} else {
			stats.updatedZoneTokens[zoneId] = token
		}
	}

	static func fetchDatabaseChanges(completion: @escaping (Error?) -> Void) {
		syncProgressString = "Fetching"
		let stats = PullState()
		var finalError: Error?

		let group = DispatchGroup()
		group.enter()
		group.enter()
		fetchDBChanges(database: container.sharedCloudDatabase, stats: stats) { error in
			if let error = error {
				finalError = error
			}
			group.leave()
		}
		fetchDBChanges(database: container.privateCloudDatabase, stats: stats) { error in
			if let error = error {
				finalError = error
			}
			group.leave()
		}

		group.notify(queue: DispatchQueue.main) {
			if finalError == nil {
				stats.commitChanges()
			}
			completion(finalError)
		}
	}

	private static func fetchDBChanges(database: CKDatabase, stats: PullState, completion: @escaping (Error?) -> Void) {

		log("Fetching changes from database \(database.databaseScope.rawValue)")

		var changedZoneIds = [CKRecordZoneID]()
		var deletedZoneIds = [CKRecordZoneID]()
		let databaseToken = PullState.databaseToken(for: database.databaseScope.rawValue)
		let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseToken)
		operation.recordZoneWithIDChangedBlock = { changedZoneIds.append($0) }
		operation.recordZoneWithIDWasPurgedBlock = { deletedZoneIds.append($0) }
		operation.recordZoneWithIDWasDeletedBlock = { deletedZoneIds.append($0) }
		operation.fetchDatabaseChangesCompletionBlock = { newToken, _, error in
			if let error = error {
				log("Shared database fetch operation failed: \(error.finalDescription)")
				DispatchQueue.main.async {
					completion(error)
				}
				return
			}

			DispatchQueue.main.async {
				for deletedZoneId in deletedZoneIds {
					log("Detected zone deletion: \(deletedZoneId)")
					Model.removeItemsFromZone(deletedZoneId)
					PullState.setZoneToken(nil, for: deletedZoneId)
				}
			}

			if changedZoneIds.isEmpty {
				log("No database changes detected")
				DispatchQueue.main.async {
					stats.updatedDatabaseTokens[database.databaseScope.rawValue] = newToken
					completion(nil)
				}
				return
			}

			fetchZoneChanges(database: database, zoneIDs: changedZoneIds, stats: stats) { error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error fetching zone changes for \(database): \(error.finalDescription)")
					} else {
						stats.updatedDatabaseTokens[database.databaseScope.rawValue] = newToken
					}
					completion(error)
				}
			}
		}
		operation.qualityOfService = .userInitiated
		database.add(operation)
	}

	private static func fetchZoneChanges(database: CKDatabase, zoneIDs: [CKRecordZoneID], stats: PullState, completion: @escaping (Error?) -> Void) {

		log("Fetching changes to \(zoneIDs.count) zone(s) in database \(database.databaseScope.rawValue)")

		var optionsByRecordZoneID = [CKRecordZoneID: CKFetchRecordZoneChangesOptions]()
		for zoneID in zoneIDs {
			let options = CKFetchRecordZoneChangesOptions()
			options.previousServerChangeToken = PullState.zoneToken(for: zoneID)
			optionsByRecordZoneID[zoneID] = options
		}

		let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, optionsByRecordZoneID: optionsByRecordZoneID)
		operation.recordWithIDWasDeletedBlock = { recordId, recordType in
			recordDeleted(recordId: recordId, recordType: recordType, stats: stats)
		}
		operation.recordChangedBlock = { record in
			recordChanged(record: record, stats: stats)
		}
		operation.recordZoneFetchCompletionBlock = { (zoneId, token, _, _, error) in
			zoneFetchDone(zoneId: zoneId, token: token, error: error, stats: stats)
		}
		operation.fetchRecordZoneChangesCompletionBlock = { error in
			completion(error)
		}

		database.add(operation)
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

	static func share(item: ArchivedDropItem, rootRecord: CKRecord, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
		let shareRecord = CKShare(rootRecord: rootRecord)
		shareRecord[CKShareTitleKey] = item.displayTitleOrUuid as NSString
		if let ip = item.imagePath, let data = NSData(contentsOf: ip) {
			shareRecord[CKShareThumbnailImageDataKey] = data
		}
		let typeItemsThatNeedMigrating = item.typeItems.filter { $0.cloudKitRecord?.parent == nil }
		let recordsToSave = [rootRecord, shareRecord] + typeItemsThatNeedMigrating.compactMap { $0.populatedCloudKitRecord }
		let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: [])
		operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
			completion(shareRecord, container, error)
		}
		go(operation)
	}

	static func acceptShare(_ metadata: CKShareMetadata) {
		if !syncSwitchedOn { return }
		showNetwork = true
		let acceptShareOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
		acceptShareOperation.acceptSharesCompletionBlock = { error in
			DispatchQueue.main.async {
				showNetwork = false
				if let error = error {
					genericAlert(title: "Could not accept share", message: error.finalDescription, on: ViewController.shared)
				}
			}
		}
		acceptShareOperation.qualityOfService = .userInteractive
		CKContainer(identifier: metadata.containerIdentifier).add(acceptShareOperation)
	}
}
