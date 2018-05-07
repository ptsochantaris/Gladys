//
//  CloudManager.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import CloudKit

extension CloudManager {

	static func received(notificationInfo: [AnyHashable : Any]) {
		NSApplication.shared.dockTile.badgeLabel = ""
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			Model.reloadDataIfNeeded()
			sync { error in
				if let error = error {
					log("Push sync result: \(error.finalDescription)")
				} else {
					log("Push sync done")
				}
			}
		}
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
					genericAlert(title: "Sync Failure", message: "You are not logged into iCloud anymore, so sync was disabled.")
				} else {
					genericAlert(title: "Sync Failure", message: "You have changed iCloud accounts. iCloud sync was disabled to keep your data safe. You can re-activate it to upload all your data to this account as well.")
				}
				return
			}
		}

		_sync(force: force) { error in
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
					genericAlert(title: "Sync Failure", message: "There was an irrecoverable failure in sync and it has been disabled:\n\n\"\(e.finalDescription)\"")
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
					_sync(force: force, completion: completion)
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

	static private func _sync(force: Bool, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { completion(nil); return }

		if syncing && !force {
			syncDirty = true
			completion(nil)
			return
		}

		syncing = true
		syncDirty = false

		func done(_ error: Error?) {
			syncing = false
			if let e = error {
				log("Sync failure: \(e.finalDescription)")
			}
			completion(error)
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
					_sync(force: true, completion: completion)
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}
}
