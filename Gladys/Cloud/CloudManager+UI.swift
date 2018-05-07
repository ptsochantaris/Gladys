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
