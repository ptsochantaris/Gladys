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

	private static var d: UserDefaults = { return UserDefaults(suiteName: "group.build.bru.Gladys")! }()

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

	static var lastSyncCompletion: Date {
		get {
			return d.object(forKey: "lastSyncCompletion") as? Date ?? .distantPast
		}

		set {
			d.set(newValue, forKey: "lastSyncCompletion")
			d.synchronize()
		}
	}

	static var zoneChangeMayNotReflectSavedChanges: Bool {
		get {
			return d.bool(forKey: "zoneChangeMayNotReflectSavedChanges")
		}

		set {
			d.set(newValue, forKey: "zoneChangeMayNotReflectSavedChanges")
			d.synchronize()
		}
	}

	static var syncSwitchedOn: Bool {
		get {
			return d.bool(forKey: "syncSwitchedOn")
		}

		set {
			d.set(newValue, forKey: "syncSwitchedOn")
			d.synchronize()
		}
	}

	static var onlySyncOverWiFi: Bool {
		get {
			return d.bool(forKey: "onlySyncOverWiFi")
		}

		set {
			d.set(newValue, forKey: "onlySyncOverWiFi")
			d.synchronize()
		}
	}

	static var zoneChangeToken: CKServerChangeToken? {
		get {
			if let data = d.data(forKey: "zoneChangeToken"), data.count > 0 {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
			} else {
				return nil
			}
		}
		set {
			if let n = newValue {
				let data = NSKeyedArchiver.archivedData(withRootObject: n)
				d.set(data, forKey: "zoneChangeToken")
			} else {
				d.set(Data(), forKey: "zoneChangeToken")
			}
			d.synchronize()
		}
	}

	///////////////////////////////////////

	static var uuidSequence: [String] {
		get {
			if let data = d.data(forKey: "uuidSequence") {
				return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String] ?? []
			} else {
				return []
			}
		}
		set {
			let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
			d.set(data, forKey: "uuidSequence")
			d.synchronize()
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
