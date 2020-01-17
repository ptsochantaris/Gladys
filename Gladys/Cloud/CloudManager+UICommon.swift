//
//  CloudManager+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CloudKit
#if os(iOS)
import UIKit
typealias VC = UIViewController
#else
import Cocoa
typealias VC = NSViewController
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
				@unknown default:
					activationFailure(error: error, reason: "iCloud access is not available on this device.", completion: completion)
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
			completion(NSError(domain: GladysErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: reason]))
		}
	}

	static private func shutdownShares(ids: [CKRecord.ID], force: Bool, completion: @escaping (Error?)->Void) {
		let modifyOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
		modifyOperation.savePolicy = .allKeys
		modifyOperation.perRecordCompletionBlock = { record, error in
			let recordUUID = record.recordID.recordName
			DispatchQueue.main.async {
				if let item = Model.item(shareId: recordUUID) {
					item.cloudKitShareRecord = nil
					log("Shut down sharing for item \(item.uuid) before deactivation")
					item.postModified()
				}
			}
		}
		modifyOperation.modifyRecordsCompletionBlock = { _, _, error in
			DispatchQueue.main.async {
				if !force, let error = error {
					completion(error)
					log("Cloud sync deactivation failed, could not deactivate current shares")
					syncTransitioning = false
				} else {
					deactivate(force: force, deactivatingShares: false, completion: completion)
				}
			}
		}
		perform(modifyOperation, on: container.privateCloudDatabase, type: "shutdown shares")
	}

	static func deactivate(force: Bool, deactivatingShares: Bool = true, completion: @escaping (Error?)->Void) {
		syncTransitioning = true

		if deactivatingShares {
			let myOwnShareIds = Model.itemsIAmSharing.compactMap { $0.cloudKitShareRecord?.recordID }
			if !myOwnShareIds.isEmpty {
				shutdownShares(ids: myOwnShareIds, force: force, completion: completion)
				return
			}
		}

		var finalError: Error?

		let ss = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [sharedDatabaseSubscriptionId])
		ss.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				finalError = error
			}
		}
		perform(ss, on: container.sharedCloudDatabase, type: "delete subscription")

		let ms = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [privateDatabaseSubscriptionId])
		ms.modifySubscriptionsCompletionBlock = { savedSubscriptions, deletedIds, error in
			if let error = error {
				finalError = error
			}
		}
		perform(ms, on: container.privateCloudDatabase, type: "delete subscription")

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
				PersistedOptions.lastPushToken = nil
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
		doneOperation.addDependency(ms)
		OperationQueue.main.addOperation(doneOperation)
	}

	private static func subscribeToDatabaseOperation(id: String) -> CKModifySubscriptionsOperation {
		let notificationInfo = CKSubscription.NotificationInfo()
		notificationInfo.shouldSendContentAvailable = true
		notificationInfo.shouldBadge = true

		let subscription = CKDatabaseSubscription(subscriptionID: id)
		subscription.notificationInfo = notificationInfo
		return CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
	}

	private static func proceedWithActivation(completion: @escaping (Error?)->Void) {

		let zone = CKRecordZone(zoneID: privateZoneId)
		let createZone = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
		createZone.modifyRecordZonesCompletionBlock = { _, _, error in
			if let error = error {
				abortActivation(error, completion: completion)
			} else {
				DispatchQueue.main.async {
					#if os(iOS)
						UIApplication.shared.registerForRemoteNotifications()
					#else
						NSApplication.shared.registerForRemoteNotifications(matching: [])
					#endif
				}
				fetchInitialUUIDSequence(zone: zone, completion: completion)
			}
		}
		perform(createZone, on: container.privateCloudDatabase, type: "create private zone: \(privateZoneId)")
	}

	private static func updateSubscriptions(completion: @escaping (Error?)->Void) {
		let subscribeToPrivateDatabase = subscribeToDatabaseOperation(id: privateDatabaseSubscriptionId)
		subscribeToPrivateDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
			if error != nil {
				completion(error)
			} else {
				let subscribeToSharedDatabase = subscribeToDatabaseOperation(id: sharedDatabaseSubscriptionId)
				subscribeToSharedDatabase.modifySubscriptionsCompletionBlock = { _, _, error in
					completion(error)
				}
				perform(subscribeToSharedDatabase, on: container.sharedCloudDatabase, type: "subscribe to db")
			}
		}
		perform(subscribeToPrivateDatabase, on: container.privateCloudDatabase, type: "subscribe to db")
	}

	static private func abortActivation(_ error: Error, completion: @escaping (Error?)->Void) {
		DispatchQueue.main.async {
			completion(error)
			deactivate(force: true, completion: { _ in })
		}
	}

	static private func fetchInitialUUIDSequence(zone: CKRecordZone, completion: @escaping (Error?)->Void) {
		let positionListId = CKRecord.ID(recordName: RecordType.positionList, zoneID: zone.zoneID)
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
					lastiCloudAccount = FileManager.default.ubiquityIdentityToken
                    completion(nil)
				}
			}
		}

		perform(fetchInitialUUIDSequence, on: container.privateCloudDatabase, type: "fetch initial uuid sequence")
	}

	static func eraseZoneIfNeeded(completion: @escaping (Error?)->Void) {
		showNetwork = true
		let deleteZone = CKModifyRecordZonesOperation(recordZonesToSave:nil, recordZoneIDsToDelete: [privateZoneId])
		deleteZone.modifyRecordZonesCompletionBlock = { savedRecordZones, deletedRecordZoneIDs, error in
			if let error = error {
				log("Error while deleting zone: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				showNetwork = false
				completion(error)
			}
		}
		perform(deleteZone, on: container.privateCloudDatabase, type: "erase private zone")
	}

	static private func recordDeleted(recordId: CKRecord.ID, recordType: String, stats: PullState) {
		let itemUUID = recordId.recordName
        switch recordType {
        case RecordType.item:
            if let item = Model.item(uuid: itemUUID) {
                if item.parentZone != recordId.zoneID {
                    log("Ignoring delete for item \(itemUUID) from a different zone")
                } else {
                    log("Drop \(recordType) deletion: \(itemUUID)")
                    item.needsDeletion = true
                    item.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
                    item.cloudKitShareRecord = nil // get rid of useless file
                    stats.deletionCount += 1
                }
            } else {
                log("Received delete for non-existent item record \(itemUUID), ignoring")
            }
        case RecordType.component:
            if let component = Model.component(uuid: itemUUID) {
                if component.parentZone != recordId.zoneID {
                    log("Ignoring delete for component \(itemUUID) from a different zone")
                } else {
                    log("Component \(recordType) deletion: \(itemUUID)")
                    component.needsDeletion = true
                    component.cloudKitRecord = nil // no need to sync deletion up, it's already recorded in the cloud
                    stats.deletionCount += 1
                }
            } else {
                log("Received delete for non-existent component record \(itemUUID), ignoring")
            }
        case RecordType.share:
            if let associatedItem = Model.item(shareId: itemUUID) {
                if let zoneID = associatedItem.cloudKitShareRecord?.recordID.zoneID, zoneID != recordId.zoneID {
                    log("Ignoring delete for share record for item \(associatedItem.uuid) from a different zone")
                } else {
                    log("Share record deleted for item \(associatedItem.uuid)")
                    associatedItem.cloudKitShareRecord = nil
                    stats.deletionCount += 1
                }
            } else {
                log("Received delete for non-existent share record \(itemUUID), ignoring")
            }
        default:
            log("Warning: Received deletion for unknown record type: \(recordType)")
        }
	}

    static private func recordChanged(record: CKRecord, stats: PullState) {
        let recordID = record.recordID
        let zoneID = recordID.zoneID
        let recordUUID = recordID.recordName
        switch record.recordType {
        case RecordType.item:
            if let item = Model.item(uuid: recordUUID) {
                if item.parentZone != zoneID {
                    log("Ignoring update notification for existing item UUID but wrong zone (\(recordUUID))")
                } else if record.recordChangeTag == item.cloudKitRecord?.recordChangeTag {
                    log("Update but no changes to item record (\(recordUUID))")
                } else {
                    log("Will update existing local item for cloud record \(recordUUID)")
                    item.cloudKitUpdate(from: record)
                    item.needsReIngest = true
                    item.postModified()
                    stats.updateCount += 1
                }
            } else {
                log("Will create new local item for cloud record (\(recordUUID))")
                let newItem = ArchivedItem(from: record)
                let newTypeItemRecords = stats.pendingTypeItemRecords.filter {
                    $0.parent?.recordID == recordID // takes zone into account
                }
                if !newTypeItemRecords.isEmpty {
                    let uuid = newItem.uuid
                    newItem.components.append(contentsOf: newTypeItemRecords.map { Component(from: $0, parentUuid: uuid) })
                    stats.pendingTypeItemRecords = stats.pendingTypeItemRecords.filter { !newTypeItemRecords.contains($0) }
                    log("  Hooked \(newTypeItemRecords.count) pending type items")
                }
                if let existingShareId = record.share?.recordID, let pendingShareIndex = stats.pendingShareRecords.firstIndex(where: {
                    $0.recordID == existingShareId // takes zone into account
                }) {
                    newItem.cloudKitShareRecord = stats.pendingShareRecords[pendingShareIndex]
                    stats.pendingShareRecords.remove(at: pendingShareIndex)
                    log("  Hooked onto pending share \((existingShareId.recordName))")
                }
                Model.drops.append(newItem)
                NotificationCenter.default.post(name: .ItemAddedBySync, object: newItem)
                stats.newDropCount += 1
            }
            
        case RecordType.component:
            if let typeItem = Model.component(uuid: recordUUID) {
                if typeItem.parentZone != zoneID {
                    log("Ignoring update notification for existing component UUID but wrong zone (\(recordUUID))")
                } else if record.recordChangeTag == typeItem.cloudKitRecord?.recordChangeTag {
                    log("Update but no changes to item type data record (\(recordUUID))")
                } else {
                    log("Will update existing local type data: (\(recordUUID))")
                    typeItem.cloudKitUpdate(from: record)
                    stats.typeUpdateCount += 1
                }
            } else if let parentId = (record["parent"] as? CKRecord.Reference)?.recordID.recordName, let existingParent = Model.item(uuid: parentId) {
                if existingParent.parentZone != zoneID {
                    log("Ignoring new component for existing item UUID but wrong zone (component: \(recordUUID) item: \(parentId))")
                } else {
                    log("Will create new local type data (\(recordUUID)) for parent (\(parentId))")
                    existingParent.components.append(Component(from: record, parentUuid: existingParent.uuid))
                    stats.newTypeItemCount += 1
                }
            } else {
                stats.pendingTypeItemRecords.append(record)
                log("Received new type item (\(recordUUID)) to link to upcoming new item")
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
                if let associatedItem = Model.item(shareId: recordUUID) {
                    if associatedItem.parentZone != zoneID {
                        log("Ignoring share record updated for existing item in different zone (share: \(recordUUID) - item: \(associatedItem.uuid))")
                    } else {
                        log("Share record updated for item (share: \(recordUUID) - item: \(associatedItem.uuid))")
                        associatedItem.cloudKitShareRecord = share
                        stats.updateCount += 1
                    }
                } else {
                    stats.pendingShareRecords.append(share)
                    log("Received new share record (\(recordUUID)) to potentially link to upcoming new item")
                }
            }
            
        default:
            log("Warning: Received record update for unkown type: \(record.recordType)")
        }
    }

	static private func zoneFetchDone(zoneId: CKRecordZone.ID, token: CKServerChangeToken?, error: Error?, stats: PullState) -> Bool {
		if (error as? CKError)?.code == .changeTokenExpired {
			DispatchQueue.main.async {
				PullState.setZoneToken(nil, for: zoneId)
				syncProgressString = "Fetching Full Update…"
			}
			log("Zone \(zoneId.zoneName) changes fetch had stale token, will retry")
			return true
		} else {
			stats.updatedZoneTokens[zoneId] = token
			return false
		}
	}

	static private func fetchDatabaseChanges(scope: CKDatabase.Scope?, completion: @escaping (Error?) -> Void) {
		syncProgressString = "Checking"
		let stats = PullState()
		var finalError: Error?
		var shouldCommitTokens = true
		let group = DispatchGroup()

		let changeCallback = { (error: Error?, skipCommit: Bool) in
			if let error = error {
				finalError = error
				shouldCommitTokens = false

			} else if skipCommit {
				shouldCommitTokens = false
			}
			group.leave()
		}

		if scope == nil || scope == .shared {
			group.enter()
			fetchDBChanges(database: container.sharedCloudDatabase, stats: stats, completion: changeCallback)
		}

		if scope == nil || scope == .private {
			group.enter()
			fetchDBChanges(database: container.privateCloudDatabase, stats: stats, completion: changeCallback)
		}

		group.notify(queue: DispatchQueue.main) {
			if finalError == nil && shouldCommitTokens {
				fetchMissingShareRecords { error in
					stats.processChanges(commitTokens: shouldCommitTokens)
					completion(error)
				}
			} else {
				stats.processChanges(commitTokens: shouldCommitTokens)
				completion(finalError)
			}
		}
	}

	private static func fetchMissingShareRecords(completion: @escaping (Error?)->Void) {

		var fetchGroups = [CKRecordZone.ID: [CKRecord.ID]]()

		for item in Model.drops {
			if let shareId = item.cloudKitRecord?.share?.recordID, item.cloudKitShareRecord == nil {
				let zoneId = shareId.zoneID
				if var existingFetchGroup = fetchGroups[zoneId] {
					existingFetchGroup.append(shareId)
					fetchGroups[zoneId] = existingFetchGroup
				} else {
					fetchGroups[zoneId] = [shareId]
				}
			}
		}

		if fetchGroups.isEmpty {
			completion(nil)
			return
		}

		var finalError: Error?

		let doneOperation = BlockOperation {
			if let finalError = finalError {
				log("Error fetching missing share records: \(finalError.finalDescription)")
			}
			completion(finalError)
		}

		for zoneId in fetchGroups.keys {
			guard let fetchGroup = fetchGroups[zoneId] else { continue }
			let fetch = CKFetchRecordsOperation(recordIDs: fetchGroup)
			fetch.perRecordCompletionBlock = { record, recordID, error in
				DispatchQueue.main.async {
					if let error = error {
						if error.itemDoesNotExistOnServer, let recordID = recordID {
							// this share record does not exist. Our local data is wrong
							if let itemWithShare = Model.item(shareId: recordID.recordName) {
								log("Warning: Our local data thinks we have a share in the cloud (\(recordID.recordName) for item (\(itemWithShare.uuid.uuidString), but no such record exists. Trying a rescue of the remote record.")
								fetchCloudRecord(for: itemWithShare, completion: nil)
							}
						} else {
							finalError = error
						}
					}
					if let share = record as? CKShare, let existingItem = Model.item(shareId: share.recordID.recordName) {
						existingItem.cloudKitShareRecord = share
					}
				}
			}
			doneOperation.addDependency(fetch)
			let database = zoneId == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
			perform(fetch, on: database, type: "fetch missing share records for items")
		}

		OperationQueue.main.addOperation(doneOperation)
	}

	private static func fetchCloudRecord(for item: ArchivedItem?, completion: ((Error?) -> Void)?) {
		guard let itemNeedingCloudPull = item, let recordIdNeedingRefresh = itemNeedingCloudPull.cloudKitRecord?.recordID else { return }
		let fetch = CKFetchRecordsOperation(recordIDs: [recordIdNeedingRefresh])
		fetch.perRecordCompletionBlock = { record, _, error in
			if let record = record {
				DispatchQueue.main.async {
					log("Replaced local cloud record with latest copy from server (\(itemNeedingCloudPull.uuid))")
					itemNeedingCloudPull.cloudKitRecord = record
					itemNeedingCloudPull.postModified()
				}
			} else if let error = error, error.itemDoesNotExistOnServer {
				DispatchQueue.main.async {
					log("Determined no cloud record exists for item, clearing local related cloud records so next sync can re-create them (\(itemNeedingCloudPull.uuid))")
					itemNeedingCloudPull.removeFromCloudkit()
					itemNeedingCloudPull.postModified()
				}
			}
			DispatchQueue.main.async {
				completion?(error)
			}
		}
		let database = recordIdNeedingRefresh.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
		perform(fetch, on: database, type: "fetching individual cloud record")
	}

	private static func fetchDBChanges(database: CKDatabase, stats: PullState, completion: @escaping (Error?, Bool) -> Void) {

		var changedZoneIds = Set<CKRecordZone.ID>()
		var deletedZoneIds = Set<CKRecordZone.ID>()
		let databaseToken = PullState.databaseToken(for: database.databaseScope)
		let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseToken)
		operation.recordZoneWithIDChangedBlock = { changedZoneIds.insert($0) }
		operation.recordZoneWithIDWasPurgedBlock = {
			deletedZoneIds.insert($0)
			log("Detected zone purging in \(database.databaseScope.logName) database: \($0)")
		}
		operation.recordZoneWithIDWasDeletedBlock = {
			deletedZoneIds.insert($0)
			log("Detected zone deletion in \(database.databaseScope.logName) database: \($0)")
		}
		operation.fetchDatabaseChangesCompletionBlock = { newToken, _, error in
			if let error = error {
				log("\(database.databaseScope.logName) database fetch operation failed: \(error.finalDescription)")
				DispatchQueue.main.async {
					completion(error, false)
				}
				return
			}

			if deletedZoneIds.contains(privateZoneId) {
				if database.databaseScope == .private {
					log("Private zone has been deleted, sync must be disabled.")
					DispatchQueue.main.async {
						genericAlert(title: "Your Gladys iCloud zone was deleted from another device.", message: "Sync was disabled in order to protect the data on this device.\n\nYou can re-create your iCloud data store with data from here if you turn sync back on again.")
						deactivate(force: true) { _ in
							completion(nil, true)
						}
					}
					return
				} else {
					log("Private zone has been signaled as deleted in \(database.databaseScope.logName) database, ignoring this")
					deletedZoneIds.remove(privateZoneId)
				}
			}

			DispatchQueue.main.async {
				for deletedZoneId in deletedZoneIds {
					log("Handling zone deletion in \(database.databaseScope.logName) database: \(deletedZoneId)")
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

			fetchZoneChanges(database: database, zoneIDs: Array(changedZoneIds), stats: stats) { error in
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
		perform(operation, on: database, type: "fetch database changes")
	}
    
	private static func fetchZoneChanges(database: CKDatabase, zoneIDs: [CKRecordZone.ID], stats: PullState, completion: @escaping (Error?) -> Void) {

		log("Fetching changes to \(zoneIDs.count) zone(s) in \(database.databaseScope.logName) database")

        #if os(iOS)
        typealias ZoneConfig=CKFetchRecordZoneChangesOperation.ZoneConfiguration
        #else
        typealias ZoneConfig=CKFetchRecordZoneChangesOperation.ZoneOptions
        #endif

		var needsRetry = false
		var configurationsByRecordZoneID = [CKRecordZone.ID: ZoneConfig]()
		for zoneID in zoneIDs {
            let options = ZoneConfig()
			options.previousServerChangeToken = PullState.zoneToken(for: zoneID)
			configurationsByRecordZoneID[zoneID] = options
		}

        #if os(iOS)
		let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: configurationsByRecordZoneID)
        #else
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, optionsByRecordZoneID: configurationsByRecordZoneID)
        #endif
		operation.recordWithIDWasDeletedBlock = { recordId, recordType in
            DispatchQueue.main.sync {
                recordDeleted(recordId: recordId, recordType: recordType, stats: stats)
            }
		}
		operation.recordChangedBlock = { record in
            DispatchQueue.main.sync {
                recordChanged(record: record, stats: stats)
            }
		}
		operation.recordZoneFetchCompletionBlock = { zoneId, token, _, _, error in
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

		perform(operation, on: database, type: "fetch zone changes")
	}

	static func sync(scope: CKDatabase.Scope? = nil, force: Bool = false, overridingWiFiPreference: Bool = false, completion: @escaping (Error?)->Void) {

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

		@unknown default:
			// not handled, let's assume it's important
			completion(ckError)
		}
	}

	static func share(item: ArchivedItem, rootRecord: CKRecord, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
		let shareRecord = CKShare(rootRecord: rootRecord)
		shareRecord[CKShare.SystemFieldKey.title] = item.trimmedSuggestedName as NSString
		let icon = item.displayIcon
        let scaledIcon = icon.limited(to: Component.iconPointSize, limitTo: 1, useScreenScale: false, singleScale: true)
		#if os(iOS)
		shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.pngData() as NSData?
		#else
		shareRecord[CKShare.SystemFieldKey.thumbnailImageData] = scaledIcon.tiffRepresentation as NSData?
		#endif
		let componentsThatNeedMigrating = item.components.filter { $0.cloudKitRecord?.parent == nil }.compactMap { $0.populatedCloudKitRecord }
		let recordsToSave = [rootRecord, shareRecord] + componentsThatNeedMigrating
		let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: [])
		operation.savePolicy = .allKeys
		operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
			completion(shareRecord, container, error)
		}
		perform(operation, on: container.privateCloudDatabase, type: "share item")
	}

	static func acceptShare(_ metadata: CKShare.Metadata) {
		if !syncSwitchedOn {
			genericAlert(title: "Could not accept shared item", message: "You need to enable iCloud sync from preferences before accepting items shared in iCloud")
			return
		}
		if let existingItem = Model.item(uuid: metadata.rootRecordID.recordName) {
            let request = HighlightRequest(uuid: existingItem.uuid.uuidString)
            NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
			return
		}
		NotificationCenter.default.post(name: .AcceptStarting, object: nil)
		sync { _ in // make sure all our previous deletions related to shares are caught up in the change tokens, just in case
			showNetwork = true
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
			acceptShareOperation.qualityOfService = .userInitiated
			CKContainer(identifier: metadata.containerIdentifier).add(acceptShareOperation)
		}
	}

	static func deleteShare(_ item: ArchivedItem, completion: @escaping (Error?)->Void) {
		guard let shareId = item.cloudKitRecord?.share?.recordID ?? item.cloudKitShareRecord?.recordID else {
			completion(nil)
			return
		}
		let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [shareId])
		deleteOperation.perRecordCompletionBlock = { _, error in
			DispatchQueue.main.async {
				if let error = error, !error.itemDoesNotExistOnServer {
					genericAlert(title: "There was an error while un-sharing this item", message: error.finalDescription)
					completion(error)
				} else { // our local record must be stale, let's refresh it just in case
					item.cloudKitShareRecord = nil
					fetchCloudRecord(for: item, completion: completion)
				}
			}
		}
		let database = shareId.zoneID == privateZoneId ? container.privateCloudDatabase : container.sharedCloudDatabase
		perform(deleteOperation, on: database, type: "delete share")
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
                } else {
                    sync(force: true, overridingWiFiPreference: true) { error in
                        if let error = error {
                            genericAlert(title: "Initial sync failed", message: error.finalDescription)
                        }
                    }
                }
			}
		}
	}

	private static func attemptSync(scope: CKDatabase.Scope?, force: Bool, overridingWiFiPreference: Bool, completion: @escaping (Error?)->Void) {
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
		BackgroundTask.registerForBackground()
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
			BackgroundTask.unregisterForBackground()
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
					attemptSync(scope: nil, force: true, overridingWiFiPreference: overridingWiFiPreference, completion: completion)
					#if os(iOS)
					BackgroundTask.unregisterForBackground()
					#endif
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}

	static func apnsUpdate(_ newToken: Data?) {
		let previousToken = PersistedOptions.lastPushToken
		if newToken != previousToken {
			if let newToken = newToken {
				log("New APNS token, will update subscriptions")
				updateSubscriptions { error in
					if let error = error {
						log("Subscription update failed: \(error)")
					} else {
						log("Subscriptions updated successfully, storing new token")
						DispatchQueue.main.async {
							PersistedOptions.lastPushToken = newToken
						}
					}
				}
			} else {
				PersistedOptions.lastPushToken = nil
			}
		}
	}
}
