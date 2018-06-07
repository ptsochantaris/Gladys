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

		let positionListId = CKRecordID(recordName: RecordType.positionList, zoneID: zone.zoneID)
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

	private class SyncState {
		var updatedSequence = false
		var newDrops = [CKRecord]() { didSet { updateProgress() } }
		var newTypeItemsToHookOntoDrops = [CKRecord]() { didSet { updateProgress() } }

		var typeUpdateCount = 0 { didSet { updateProgress() } }
		var deletionCount = 0 { didSet { updateProgress() } }
		var updateCount = 0 { didSet { updateProgress() } }
		var newTypesAppended = 0

		let previousToken = zoneChangeToken
		var newToken: CKServerChangeToken?

		var itemsModified: Bool {
			return typeUpdateCount + newDrops.count + updateCount + deletionCount + newTypesAppended > 0
		}

		private func updateProgress() {
			var components = [String]()

			let newCount = newDrops.count
			if newCount > 0 { components.append(newCount == 1 ? "1 Drop" : "\(newCount) Drops") }
			if updateCount > 0 { components.append(updateCount == 1 ? "1 Update" : "\(updateCount) Updates") }

			let newTypeCount = newTypeItemsToHookOntoDrops.count
			if newTypeCount > 0 { components.append(newTypeCount == 1 ? "1 Component" : "\(newTypeCount) Components") }

			if typeUpdateCount > 0 { components.append(typeUpdateCount == 1 ? "1 Component Update" : "\(typeUpdateCount) Component Updates") }

			if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }

			if components.count > 0 {
				syncProgressString = "Fetched " + components.joined(separator: ", ")
			} else {
				syncProgressString = "Fetching"
			}
		}
	}

	static private func recordDeleted(recordId: CKRecordID, recordType: String, stats: SyncState) {
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

	static private func recordChanged(record: CKRecord, stats: SyncState) {
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
				if let share = record as? CKShare, let associatedItem = Model.item(shareId: itemUUID) {
					log("Share record updated for item \(associatedItem.uuid)")
					associatedItem.cloudKitShareRecord = share
					stats.updateCount += 1
				}
			default:
				log("Warning: Received record update for unkown type: \(recordType)")
			}
		}
	}

	static private func applyChanges(stats: SyncState) {
		log("Private zone changes fetch complete, processing")

		for newTypeItemRecord in stats.newTypeItemsToHookOntoDrops {
			if let parentId = (newTypeItemRecord["parent"] as? CKReference)?.recordID.recordName, let existingParent = Model.item(uuid: parentId) {
				let newTypeItem = ArchivedDropItemType(from: newTypeItemRecord, parentUuid: existingParent.uuid)
				existingParent.typeItems.append(newTypeItem)
				existingParent.needsReIngest = true
				stats.newTypesAppended += 1
			}
		}
		for dropRecord in stats.newDrops {
			createNewArchivedDrop(from: dropRecord, drawChildrenFrom: stats.newTypeItemsToHookOntoDrops)
		}

		if stats.updatedSequence || stats.newDrops.count > 0 {
			let sequence = uuidSequence.compactMap { UUID(uuidString: $0) }
			if sequence.count > 0 {
				Model.drops.sort { i1, i2 in
					let p1 = sequence.index(of: i1.uuid) ?? -1
					let p2 = sequence.index(of: i2.uuid) ?? -1
					return p1 < p2
				}
			}
		}

		let itemsModified = stats.itemsModified

		if itemsModified || stats.updatedSequence {
			log("Posting external data update notification")
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
		}

		if itemsModified {
			// need to save stuff that's been modified
			Model.queueNextSaveCallback {
				log("Comitting zone change token")
				self.zoneChangeToken = stats.newToken
			}
			Model.saveIsDueToSyncFetch = true
			Model.save()
		} else if stats.previousToken != stats.newToken {
			// it was only a position record, most likely
			if stats.updatedSequence {
				Model.saveIndexOnly()
			}
			log("Comitting zone change token")
			self.zoneChangeToken = stats.newToken
		} else {
			log("No updates available")
		}
	}

	static private func zoneFetchDone(zoneId: CKRecordZoneID, token: CKServerChangeToken?, error: Error?, stats: SyncState) {
		stats.newToken = token
		if (error as? CKError)?.code == .changeTokenExpired {
			DispatchQueue.main.async {
				zoneChangeToken = nil
				syncProgressString = "Retrying"
				log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
			}
		} else {
			DispatchQueue.main.async {
				syncProgressString = "Applying updates"
			}
			DispatchQueue.main.async {
				applyChanges(stats: stats)
			}
		}
	}

	static func fetchDatabaseChanges(finalCompletion: @escaping (Error?)->Void) {

		syncProgressString = "Fetching"
		let stats = SyncState()

		let o = CKFetchRecordZoneChangesOptions()
		o.previousServerChangeToken = stats.previousToken
		let zoneId = CKRecordZoneID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)
		let fetchZoneChanges = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneId], optionsByRecordZoneID: [zoneId : o])
		fetchZoneChanges.recordWithIDWasDeletedBlock = { recordId, recordType in
			recordDeleted(recordId: recordId, recordType: recordType, stats: stats)
		}
		fetchZoneChanges.recordChangedBlock = { record in
			recordChanged(record: record, stats: stats)
		}
		fetchZoneChanges.recordZoneFetchCompletionBlock = { (zoneId: CKRecordZoneID, token: CKServerChangeToken?, _, _, error: Error?) in
			zoneFetchDone(zoneId: zoneId, token: token, error: error, stats: stats)
		}
		fetchZoneChanges.fetchRecordZoneChangesCompletionBlock = { (error: Error?) in
			DispatchQueue.main.async {
				finalCompletion(error)
			}
		}

		go(fetchZoneChanges)
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
		let operation = CKModifyRecordsOperation(recordsToSave: [rootRecord, shareRecord], recordIDsToDelete: [])
		operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
			completion(shareRecord, container, error)
		}

		go(operation)
	}

	static func acceptShare(_ metadata: CKShareMetadata) {
		let acceptShareOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
		acceptShareOperation.acceptSharesCompletionBlock = { error in
			if let error = error {
				genericAlert(title: "Could not accept share", message: error.finalDescription, on: ViewController.shared)
			}
		}
		acceptShareOperation.qualityOfService = .userInteractive
		CKContainer(identifier: metadata.containerIdentifier).add(acceptShareOperation)
	}
}
