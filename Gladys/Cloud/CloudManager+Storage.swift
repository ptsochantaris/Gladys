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
			let o = PersistedOptions.defaults.object(forKey: "lastiCloudAccount") as? iCloudToken
			return (o?.isEqual("") ?? false) ? nil : o
 		}
		set {
			if let n = newValue {
				PersistedOptions.defaults.set(n, forKey: "lastiCloudAccount")
			} else {
				PersistedOptions.defaults.set("", forKey: "lastiCloudAccount") // this will return nil when fetched
			}
			PersistedOptions.defaults.synchronize()
		}
	}

	static var lastSyncCompletion: Date {
		get {
			return PersistedOptions.defaults.object(forKey: "lastSyncCompletion") as? Date ?? .distantPast
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "lastSyncCompletion")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var syncSwitchedOn: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "syncSwitchedOn")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "syncSwitchedOn")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var shareActionShouldUpload: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "shareActionShouldUpload")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "shareActionShouldUpload")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var shareActionIsActioningIds: [String] {
		get {
			return PersistedOptions.defaults.object(forKey: "shareActionIsActioningIds") as? [String] ?? []
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "shareActionIsActioningIds")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var onlySyncOverWiFi: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "onlySyncOverWiFi")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "onlySyncOverWiFi")
			PersistedOptions.defaults.synchronize()
		}
	}

	static var zoneChangeToken: CKServerChangeToken? {
		get {
			if let data = PersistedOptions.defaults.data(forKey: "zoneChangeToken"), data.count > 0 {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
			} else {
				return nil
			}
		}
		set {
			if let n = newValue {
				let data = NSKeyedArchiver.archivedData(withRootObject: n)
				PersistedOptions.defaults.set(data, forKey: "zoneChangeToken")
			} else {
				PersistedOptions.defaults.set(Data(), forKey: "zoneChangeToken")
			}
			PersistedOptions.defaults.synchronize()
		}
	}

	///////////////////////////////////////

	static var uuidSequence: [String] {
		get {
			if let data = PersistedOptions.defaults.data(forKey: "uuidSequence") {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String] ?? []
			} else {
				return []
			}
		}
		set {
			let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
			PersistedOptions.defaults.set(data, forKey: "uuidSequence")
			PersistedOptions.defaults.synchronize()
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
