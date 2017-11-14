//
//  CloudManager+Storage.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit
#if MAINAPP
	import UIKit
#endif

private var defaults: UserDefaults = { return UserDefaults(suiteName: "group.build.bru.Gladys")! }()

class PersistedOptions {

	static func migrateBrokenDefaults() { // keep this around for a while
		if let brokenDefaults = UserDefaults(suiteName: "group.buildefaults.bru.Gladys") {
			var changes = false
			for key in ["separateItemPreference", "forceTwoColumnPreference", "lastiCloudAccount", "lastSyncCompletion", "zoneChangeMayNotReflectSavedChanges", "syncSwitchedOn", "onlySyncOverWiFi", "zoneChangeToken", "uuidSequence"] {
				if let o = brokenDefaults.object(forKey: key) {
					log("Migrating option \(key) to correct defaults group")
					defaults.set(o, forKey: key)
					brokenDefaults.removeObject(forKey: key)
					changes = true
				}
			}
			if changes {
				brokenDefaults.synchronize()
				defaults.synchronize()
			}
		}
	}

	static var removeItemsWhenDraggedOut: Bool {
		get {
			return defaults.bool(forKey: "removeItemsWhenDraggedOut")
		}
		set {
			defaults.set(newValue, forKey: "removeItemsWhenDraggedOut")
			defaults.synchronize()
		}
	}

	static var dontAutoLabelNewItems: Bool {
		get {
			return defaults.bool(forKey: "dontAutoLabelNewItems")
		}
		set {
			defaults.set(newValue, forKey: "dontAutoLabelNewItems")
			defaults.synchronize()
		}
	}


	static var separateItemPreference: Bool {
		get {
			return defaults.bool(forKey: "separateItemPreference")
		}
		set {
			defaults.set(newValue, forKey: "separateItemPreference")
			defaults.synchronize()
		}
	}

	static var forceTwoColumnPreference: Bool {
		get {
			return defaults.bool(forKey: "forceTwoColumnPreference")
		}
		set {
			defaults.set(newValue, forKey: "forceTwoColumnPreference")
			defaults.synchronize()
		}
	}
}

extension CloudManager {

	static var syncTransitioning = false {
		didSet {
			if syncTransitioning != oldValue {
				#if MAINAPP
				UIApplication.shared.isNetworkActivityIndicatorVisible = syncing || syncTransitioning
				#endif
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	static var syncing = false {
		didSet {
			if syncing != oldValue {
				syncProgressString = syncing ? "Syncing" : nil
				#if MAINAPP
				UIApplication.shared.isNetworkActivityIndicatorVisible = syncing || syncTransitioning
				#endif
				NotificationCenter.default.post(name: .CloudManagerStatusChanged, object: nil)
			}
		}
	}

	typealias iCloudToken = (NSCoding & NSCopying & NSObjectProtocol)
	static var lastiCloudAccount: iCloudToken? {
		get {
			let o = defaults.object(forKey: "lastiCloudAccount") as? iCloudToken
			return (o?.isEqual("") ?? false) ? nil : o
 		}
		set {
			if let n = newValue {
				defaults.set(n, forKey: "lastiCloudAccount")
			} else {
				defaults.set("", forKey: "lastiCloudAccount") // this will return nil when fetched
			}
			defaults.synchronize()
		}
	}

	static var lastSyncCompletion: Date {
		get {
			return defaults.object(forKey: "lastSyncCompletion") as? Date ?? .distantPast
		}

		set {
			defaults.set(newValue, forKey: "lastSyncCompletion")
			defaults.synchronize()
		}
	}

	static var syncSwitchedOn: Bool {
		get {
			return defaults.bool(forKey: "syncSwitchedOn")
		}

		set {
			defaults.set(newValue, forKey: "syncSwitchedOn")
			defaults.synchronize()
		}
	}

	static var shareActionShouldUpload: Bool {
		get {
			return defaults.bool(forKey: "shareActionShouldUpload")
		}

		set {
			defaults.set(newValue, forKey: "shareActionShouldUpload")
			defaults.synchronize()
		}
	}

	static var shareActionIsActioningIds: [String] {
		get {
			return defaults.object(forKey: "shareActionIsActioningIds") as? [String] ?? []
		}

		set {
			defaults.set(newValue, forKey: "shareActionIsActioningIds")
			defaults.synchronize()
		}
	}

	static var onlySyncOverWiFi: Bool {
		get {
			return defaults.bool(forKey: "onlySyncOverWiFi")
		}

		set {
			defaults.set(newValue, forKey: "onlySyncOverWiFi")
			defaults.synchronize()
		}
	}

	static var zoneChangeToken: CKServerChangeToken? {
		get {
			if let data = defaults.data(forKey: "zoneChangeToken"), data.count > 0 {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
			} else {
				return nil
			}
		}
		set {
			if let n = newValue {
				let data = NSKeyedArchiver.archivedData(withRootObject: n)
				defaults.set(data, forKey: "zoneChangeToken")
			} else {
				defaults.set(Data(), forKey: "zoneChangeToken")
			}
			defaults.synchronize()
		}
	}

	///////////////////////////////////////

	static var uuidSequence: [String] {
		get {
			if let data = defaults.data(forKey: "uuidSequence") {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String] ?? []
			} else {
				return []
			}
		}
		set {
			let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
			defaults.set(data, forKey: "uuidSequence")
			defaults.synchronize()
		}
	}

	static var uuidSequenceRecordPath: URL {
		return Model.appStorageUrl.appendingPathComponent("ck-uuid-sequence", isDirectory: false)
	}

	static var uuidSequenceRecord: CKRecord? {
		get {
			let recordLocation = uuidSequenceRecordPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = NSKeyedUnarchiver(forReadingWith: data)
				return CKRecord(coder: coder)
			} else {
				return nil
			}
		}
		set {
			let recordLocation = uuidSequenceRecordPath
			if newValue == nil {
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			} else {
				let data = NSMutableData()
				let coder = NSKeyedArchiver(forWritingWith: data)
				newValue?.encodeSystemFields(with: coder)
				coder.finishEncoding()
				try? data.write(to: recordLocation, options: .atomic)
			}
		}
	}

	///////////////////////////////////

	static var deleteQueuePath: URL {
		return Model.appStorageUrl.appendingPathComponent("ck-delete-queue", isDirectory: false)
	}

	static var deletionQueue: Set<String> {
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
}
