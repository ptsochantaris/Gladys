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
typealias VC = UIViewController
#else
import Cocoa
typealias VC = NSViewController
typealias UIBackgroundTaskIdentifier = Int
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

	static private func shutdownShares(ids: [CKRecordID], force: Bool, completion: @escaping (Error?)->Void) {
		let modifyOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
		modifyOperation.database = container.privateCloudDatabase
		modifyOperation.perRecordCompletionBlock = { record, error in
			let recordUUID = record.recordID.recordName
			DispatchQueue.main.async {
				if let item = Model.item(shareId: recordUUID) {
					item.cloudKitShareRecord = nil
					log("Shut down sharing for item \(item.uuid) before deactivation")
				}
			}
		}
		modifyOperation.modifyRecordsCompletionBlock = { _, _, error in
			DispatchQueue.main.async {
				if !force, let error = error {
					completion(error)
				} else {
					deactivate(force: force, deactivatingShares: false, completion: completion)
				}
			}
		}
		perform(modifyOperation)
	}

	static func deactivate(force: Bool, deactivatingShares: Bool = true, completion: @escaping (Error?)->Void) {
		syncTransitioning = true

		if deactivatingShares {
			let myOwnShareIds = Model.itemsIAmSharing.compactMap { $0.cloudKitShareRecord?.recordID }
			if myOwnShareIds.count > 0 {
				shutdownShares(ids: myOwnShareIds, force: force, completion: completion)
				return
			}
		}

		var finalError: Error?

		let ss = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [sharedDatabaseSubscriptionId])
		ss.database = container.sharedCloudDatabase
		ss.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				finalError = error
			}
		}

		let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [privateDatabaseSubscriptionId])
		ms.database = container.privateCloudDatabase
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
				Model.removeImportedShares()
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
		perform(ss)

		doneOperation.addDependency(ms)
		perform(ms)

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
			subscribe.database = container.sharedCloudDatabase
			perform(subscribe)
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
		createZone.database = container.privateCloudDatabase
		createZone.modifyRecordZonesCompletionBlock = { _, _, error in
			if let error = error {
				abortActivation(error, completion: completion)
			} else {
				let subscribeToPrivateDatabase = subscribeToDatabaseOperation(id: privateDatabaseSubscriptionId)
				subscribeToPrivateDatabase.database = container.privateCloudDatabase
				subscribeToPrivateDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
					if let error = error {
						abortActivation(error, completion: completion)
					} else {
						let subscribeToSharedDatabase = subscribeToDatabaseOperation(id: sharedDatabaseSubscriptionId)
						subscribeToSharedDatabase.database = container.sharedCloudDatabase
						subscribeToSharedDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
							if let error = error {
								abortActivation(error, completion: completion)
							} else {
								fetchInitialUUIDSequence(zone: zone, completion: completion)
							}
						}
						perform(subscribeToSharedDatabase)
					}
				}
				perform(subscribeToPrivateDatabase)
			}
		}
		perform(createZone)
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
		fetchInitialUUIDSequence.database = container.privateCloudDatabase
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
					migratedSharingRecords = true
					lastiCloudAccount = FileManager.default.ubiquityIdentityToken
					sync(force: true, overridingWiFiPreference: true, completion: completion)
				}
			}
		}

		perform(fetchInitialUUIDSequence)
	}

	static func eraseZoneIfNeeded(completion: @escaping (Error?)->Void) {
		showNetwork = true
		let deleteZone = CKModifyRecordZonesOperation(recordZonesToSave:nil, recordZoneIDsToDelete: [ArchivedDropItem.privateZoneId])
		deleteZone.database = container.privateCloudDatabase
		deleteZone.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
			if let error = error {
				log("Error while deleting zone: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				showNetwork = false
				completion(error)
			}
		}
		perform(deleteZone)
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
						log("Update but no changes to item record (\(itemUUID))")
					} else {
						log("Will update existing local item for cloud record \(itemUUID)")
						item.cloudKitUpdate(from: record)
						stats.updateCount += 1
					}
				} else {
					log("Will create new local item for cloud record (\(itemUUID))")
					stats.newDrops.append(record)
				}
			case RecordType.component:
				if let typeItem = Model.typeItem(uuid: itemUUID) {
					if record.recordChangeTag == typeItem.cloudKitRecord?.recordChangeTag {
						log("Update but no changes to item type data record (\(itemUUID))")
					} else {
						log("Will update existing local type data: (\(itemUUID))")
						typeItem.cloudKitUpdate(from: record)
						stats.typeUpdateCount += 1
					}
				} else {
					log("Will create new local type data: (\(itemUUID))")
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
						log("Share record updated for item (share: \(itemUUID) - item: \(associatedItem.uuid))")
						associatedItem.cloudKitShareRecord = share
						stats.updateCount += 1
					} else {
						log("Received new share record (\(itemUUID))")
						stats.newShareItemsToSetForDrops.append(share)
					}
				}
			default:
				log("Warning: Received record update for unkown type: \(recordType)")
			}
		}
	}

	static private func zoneFetchDone(zoneId: CKRecordZoneID, token: CKServerChangeToken?, error: Error?, stats: PullState) -> Bool {
		if (error as? CKError)?.code == .changeTokenExpired {
			DispatchQueue.main.async {
				PullState.setZoneToken(nil, for: zoneId)
				syncProgressString = "Fetching Full Update..."
			}
			log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
			return true
		} else {
			stats.updatedZoneTokens[zoneId] = token
			return false
		}
	}

	static private func fetchDatabaseChanges(scope: CKDatabaseScope?, completion: @escaping (Error?) -> Void) {
		syncProgressString = "Fetching"
		let stats = PullState()
		var finalError: Error?
		var shouldCommit = true

		let group = DispatchGroup()
		if scope == nil || scope == .shared {
			group.enter()
			fetchDBChanges(database: container.sharedCloudDatabase, stats: stats) { error, skipCommit in
				if let error = error {
					finalError = error
				}
				if skipCommit {
					shouldCommit = false
				}
				group.leave()
			}
		}

		if scope == nil || scope == .private {
			group.enter()
			fetchDBChanges(database: container.privateCloudDatabase, stats: stats) { error, skipCommit in
				if skipCommit {
					shouldCommit = false
				}
				if let error = error {
					finalError = error
					group.leave()
				} else {
					if migratedSharingRecords {
						group.leave()
					} else {
						fetchMissingShareRecords {
							group.leave()
						}
					}
				}
			}
		}

		group.notify(queue: DispatchQueue.main) {
			if finalError == nil && shouldCommit {
				stats.commitChanges()
			}
			completion(finalError)
		}
	}

	private static func fetchMissingShareRecords(completion: @escaping ()->Void) {
		let itemsWithMissingShareRecords = Model.drops.compactMap { item -> CKRecordID? in
			if let shareId = item.cloudKitRecord?.share?.recordID, shareId.zoneID == ArchivedDropItem.privateZoneId, item.cloudKitShareRecord == nil {
				return shareId
			} else {
				return nil
			}
		}

		if itemsWithMissingShareRecords.count == 0 {
			migratedSharingRecords = true
			completion()
			return
		}

		let fetch = CKFetchRecordsOperation(recordIDs: itemsWithMissingShareRecords)
		fetch.perRecordCompletionBlock = { record, _, error in
			DispatchQueue.main.async {
				if let share = record as? CKShare, let existingItem = Model.item(shareId: share.recordID.recordName) {
					existingItem.cloudKitShareRecord = share
				}
			}
		}
		fetch.fetchRecordsCompletionBlock = { _, error in
			DispatchQueue.main.async {
				if error == nil {
					migratedSharingRecords = true
					NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
				}
				completion()
			}
		}
		fetch.database = container.privateCloudDatabase
		perform(fetch)
	}

	private static func fetchDBChanges(database: CKDatabase, stats: PullState, completion: @escaping (Error?, Bool) -> Void) {

		log("Fetching changes from \(database.databaseScope.logName) database")

		var changedZoneIds = [CKRecordZoneID]()
		var deletedZoneIds = [CKRecordZoneID]()
		let databaseToken = PullState.databaseToken(for: database.databaseScope)
		let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseToken)
		operation.recordZoneWithIDChangedBlock = { changedZoneIds.append($0) }
		operation.recordZoneWithIDWasPurgedBlock = { deletedZoneIds.append($0) }
		operation.recordZoneWithIDWasDeletedBlock = { deletedZoneIds.append($0) }
		operation.fetchDatabaseChangesCompletionBlock = { newToken, _, error in
			if let error = error {
				log("Shared database fetch operation failed: \(error.finalDescription)")
				DispatchQueue.main.async {
					completion(error, false)
				}
				return
			}

			if deletedZoneIds.contains(ArchivedDropItem.privateZoneId) {
				log("Private zone has been deleted, sync must be disabled.")
				DispatchQueue.main.async {
					genericAlert(title: "Your Gladys iCloud zone was deleted from another device.", message: "Sync was disabled in order to protect the data on this device.\n\nYou can re-create your iCloud data store with data from here if you turn sync back on again.")
					deactivate(force: true) { _ in
						completion(nil, true)
					}
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
				log("No database changes detected in \(database.databaseScope.logName) database")
				DispatchQueue.main.async {
					stats.updatedDatabaseTokens[database.databaseScope] = newToken
					completion(nil, false)
				}
				return
			}

			fetchZoneChanges(database: database, zoneIDs: changedZoneIds, stats: stats) { error in
				DispatchQueue.main.async {
					if let error = error {
						log("Error fetching zone changes for \(database.databaseScope.logName) database: \(error.finalDescription)")
					} else {
						stats.updatedDatabaseTokens[database.databaseScope] = newToken
					}
					completion(error, false)
				}
			}
		}
		operation.qualityOfService = .userInitiated
		database.add(operation)
	}

	private static func fetchZoneChanges(database: CKDatabase, zoneIDs: [CKRecordZoneID], stats: PullState, completion: @escaping (Error?) -> Void) {

		log("Fetching changes to \(zoneIDs.count) zone(s) in \(database.databaseScope.logName) database")

		var needsRetry = false
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
			needsRetry = zoneFetchDone(zoneId: zoneId, token: token, error: error, stats: stats)
		}
		operation.fetchRecordZoneChangesCompletionBlock = { error in
			if needsRetry {
				DispatchQueue.main.async {
					fetchZoneChanges(database: database, zoneIDs: zoneIDs, stats: stats, completion: completion)
				}
			} else {
				completion(error)
			}
		}

		database.add(operation)
	}

	static func sync(scope: CKDatabaseScope? = nil, force: Bool = false, overridingWiFiPreference: Bool = false, completion: @escaping (Error?)->Void) {

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

		attemptSync(scope: scope, force: force, overridingWiFiPreference: overridingWiFiPreference) { error in
			if let ckError = error as? CKError {
				reactToCkError(ckError, force: force, overridingWiFiPreference: overridingWiFiPreference, completion: completion)
			} else {
				completion(error)
			}
		}
	}

	private static func reactToCkError(_ ckError: CKError, force: Bool, overridingWiFiPreference: Bool, completion: @escaping (Error?)->Void) {
		switch ckError.code {

		case .notAuthenticated, .assetNotAvailable, .managedAccountRestricted, .missingEntitlement, .zoneNotFound, .incompatibleVersion,
			 .userDeletedZone, .badDatabase, .badContainer:

			// shutdown-worthy failure
			genericAlert(title: "Sync Failure", message: "There was an irrecoverable failure in sync and it was disabled:\n\n\"\(ckError.finalDescription)\"")
			deactivate(force: true) { _ in
				completion(nil)
			}

		case .assetFileModified, .changeTokenExpired, .requestRateLimited, .serverResponseLost, .serviceUnavailable, .zoneBusy:

			// retry
			let timeToRetry = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 6.0
			syncRateLimited = true
			DispatchQueue.main.asyncAfter(deadline: .now() + timeToRetry) {
				syncRateLimited = false
				attemptSync(scope: nil, force: force, overridingWiFiPreference: overridingWiFiPreference, completion: completion)
			}

		case .alreadyShared, .assetFileNotFound, .batchRequestFailed, .constraintViolation, .internalError, .invalidArguments, .limitExceeded, .permissionFailure,
			 .participantMayNeedVerification, .quotaExceeded, .referenceViolation, .serverRejectedRequest, .tooManyParticipants, .operationCancelled,
			 .resultsTruncated, .unknownItem, .serverRecordChanged, .networkFailure, .networkUnavailable, .partialFailure:

			// regular failure
			completion(ckError)
		}
	}

	static func share(item: ArchivedDropItem, rootRecord: CKRecord, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
		let shareRecord = CKShare(rootRecord: rootRecord)
		shareRecord[CKShareTitleKey] = item.cloudKitSharingTitle as NSString
		if let ip = item.imagePath, let data = NSData(contentsOf: ip) {
			shareRecord[CKShareThumbnailImageDataKey] = data
		}
		let typeItemsThatNeedMigrating = item.typeItems.filter { $0.cloudKitRecord?.parent == nil }
		let recordsToSave = [rootRecord, shareRecord] + typeItemsThatNeedMigrating.compactMap { $0.populatedCloudKitRecord }
		let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: [])
		operation.database = container.privateCloudDatabase
		operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
			completion(shareRecord, container, error)
		}
		perform(operation)
	}

	static func acceptShare(_ metadata: CKShareMetadata) {
		if !syncSwitchedOn {
			genericAlert(title: "Could not accept shared item", message: "You need to enable iCloud sync from preferences before accepting items shared in iCloud")
			return
		}
		showNetwork = true
		NotificationCenter.default.post(name: .AcceptStarting, object: nil)
		let acceptShareOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
		acceptShareOperation.acceptSharesCompletionBlock = { error in
			DispatchQueue.main.async {
				showNetwork = false
				if let error = error {
					NotificationCenter.default.post(name: .AcceptEnding, object: nil)
					genericAlert(title: "Could not accept shared item", message: error.finalDescription)
				} else {
					sync { _ in
						NotificationCenter.default.post(name: .AcceptEnding, object: nil)
					}
				}
			}
		}
		acceptShareOperation.qualityOfService = .userInteractive
		CKContainer(identifier: metadata.containerIdentifier).add(acceptShareOperation)
	}

	static func deleteShare(_ item: ArchivedDropItem, completion: @escaping (Error?)->Void) {
		guard let shareId = item.cloudKitRecord?.share?.recordID ?? item.cloudKitShareRecord?.recordID else {
			completion(nil)
			return
		}
		container.privateCloudDatabase.delete(withRecordID: shareId) { _, error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "There was an error while un-sharing this item", message: error.finalDescription)
				} else {
					item.cloudKitShareRecord = nil
					item.needsCloudPush = true
					sync(scope: .private) { error in
						item.postModified()
						completion(error)
					}
				}
			}
		}
	}

	static func proceedWithDeactivation() {
		CloudManager.deactivate(force: false) { error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "Could not change state", message: error.finalDescription)
				}
			}
		}
	}

	static func proceedWithActivation() {
		CloudManager.activate { error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "Could not change state", message: error.finalDescription)
				}
			}
		}
	}

	private static func attemptSync(scope: CKDatabaseScope?, force: Bool, overridingWiFiPreference: Bool, existingBgTask: UIBackgroundTaskIdentifier? = nil, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn {
			completion(nil)
			return
		}

		#if os(iOS)
		if !force && !overridingWiFiPreference && onlySyncOverWiFi && reachability.status != .ReachableViaWiFi {
			log("Skipping sync because no WiFi is present and user has selected WiFi sync only")
			completion(nil)
			return
		}
		#endif

		if syncing && !force {
			log("Sync already running, but need another one. Marked to retry at the end of this.")
			syncDirty = true
			completion(nil)
			return
		}

		#if os(iOS)
		let bgTask: UIBackgroundTaskIdentifier
		if let e = existingBgTask {
			bgTask = e
		} else {
			log("Starting cloud sync background task")
			bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.syncTask", expirationHandler: nil)
		}
		#else
		let bgTask: UIBackgroundTaskIdentifier? = nil
		#endif

		syncing = true
		syncDirty = false

		func done(_ error: Error?) {
			syncing = false
			if let e = error {
				log("Sync failure: \(e.finalDescription)")
			}
			completion(error)
			#if os(iOS)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				log("Ending cloud sync background task")
				UIApplication.shared.endBackgroundTask(bgTask)
			}
			#endif
		}

		sendUpdatesUp { error in
			if let error = error {
				done(error)
				return
			}

			fetchDatabaseChanges(scope: scope) { error in
				if let error = error {
					done(error)
				} else if syncDirty {
					attemptSync(scope: nil, force: true, overridingWiFiPreference: overridingWiFiPreference, existingBgTask: bgTask, completion: completion)
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}
}
