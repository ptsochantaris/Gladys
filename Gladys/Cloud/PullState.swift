import CloudKit

final class PullState {
	var updatedSequence = false
	var newDropCount = 0 { didSet { updateProgress() } }
	var newTypeItemCount = 0 { didSet { updateProgress() } }

	var typeUpdateCount = 0 { didSet { updateProgress() } }
	var deletionCount = 0 { didSet { updateProgress() } }
	var updateCount = 0 { didSet { updateProgress() } }
	var newTypesAppended = 0
	
	var updatedDatabaseTokens = [CKDatabaseScope : CKServerChangeToken]()
	var updatedZoneTokens = [CKRecordZoneID : CKServerChangeToken]()
	var pendingShareRecords = [CKShare]()
	var pendingTypeItemRecords = [CKRecord]()

	private func updateProgress() {
		var components = [String]()
		
		if newDropCount > 0 { components.append(newDropCount == 1 ? "1 Drop" : "\(newDropCount) Drops") }
		if updateCount > 0 { components.append(updateCount == 1 ? "1 Update" : "\(updateCount) Updates") }
		
		if newTypeItemCount > 0 { components.append(newTypeItemCount == 1 ? "1 Component" : "\(newTypeItemCount) Components") }
		
		if typeUpdateCount > 0 { components.append(typeUpdateCount == 1 ? "1 Component Update" : "\(typeUpdateCount) Component Updates") }
		
		if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
		
		if components.count > 0 {
			CloudManager.syncProgressString = "Fetched " + components.joined(separator: ", ")
		} else {
			CloudManager.syncProgressString = "Fetching"
		}
	}

	func processChanges(commitTokens: Bool) {
		CloudManager.syncProgressString = "Updating..."
		log("Changes fetch complete, processing")

		if updatedSequence || newDropCount > 0 {
			let sequence = CloudManager.uuidSequence.compactMap { UUID(uuidString: $0) }
			if sequence.count > 0 {
				Model.drops.sort { i1, i2 in
					let p1 = sequence.index(of: i1.uuid) ?? -1
					let p2 = sequence.index(of: i2.uuid) ?? -1
					return p1 < p2
				}
			}
		}
		
		let itemsModified = typeUpdateCount + newDropCount + updateCount + deletionCount + newTypesAppended > 0

		if itemsModified || updatedSequence {
			log("Posting external data update notification")
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
		}
		
		if itemsModified {
			// need to save stuff that's been modified
			if commitTokens {
				Model.queueNextSaveCallback {
					self.commitNewTokens()
				}
			}
			Model.saveIsDueToSyncFetch = true
			Model.save()
		} else if !updatedZoneTokens.isEmpty {
			// a position record, most likely?
			if updatedSequence {
				Model.saveIndexOnly()
			}
			if commitTokens {
				commitNewTokens()
			}
		} else {
			log("No updates available")
			if commitTokens {
				commitNewTokens()
			}
		}
	}

	private func commitNewTokens() {
		if updatedZoneTokens.count > 0 || updatedDatabaseTokens.count > 0 {
			log("Comitting change tokens")
		}
		for (zoneId, zoneToken) in updatedZoneTokens {
			PullState.setZoneToken(zoneToken, for: zoneId)
		}
		for (databaseId, databaseToken) in updatedDatabaseTokens {
			PullState.setDatabaseToken(databaseToken, for: databaseId)
		}
	}

	private static var legacyZoneChangeToken: CKServerChangeToken? {
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

	static func checkMigrations() {
		if let token = legacyZoneChangeToken {
			setZoneToken(token, for: privateZoneId)
			legacyZoneChangeToken = nil
		}
	}

	///////////////////////////////////////

	static func zoneToken(for zoneId: CKRecordZoneID) -> CKServerChangeToken? {
		if let lookup = PersistedOptions.defaults.object(forKey: "zoneTokens") as? [String : Data],
			let data = lookup[zoneId.ownerName + ":" + zoneId.zoneName],
			let token = NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken {
			return token
		}
		return nil
	}

	static func setZoneToken(_ token: CKServerChangeToken?, for zoneId: CKRecordZoneID) {
		var lookup = PersistedOptions.defaults.object(forKey: "zoneTokens") as? [String : Data] ?? [String : Data]()
		let key = zoneId.ownerName + ":" + zoneId.zoneName
		if let n = token {
			lookup[key] = NSKeyedArchiver.archivedData(withRootObject: n)
		} else {
			lookup[key] = nil
		}
		PersistedOptions.defaults.set(lookup, forKey: "zoneTokens")
		PersistedOptions.defaults.synchronize()
	}

	static func wipeZoneTokens() {
		PersistedOptions.defaults.set([String: Data](), forKey: "zoneTokens")
		PersistedOptions.defaults.synchronize()
		legacyZoneChangeToken = nil
	}

	///////////////////////////////////////

	static func databaseToken(for database: CKDatabaseScope) -> CKServerChangeToken? {
		let key = database.keyName
		if let lookup = PersistedOptions.defaults.object(forKey: "databaseTokens") as? [String : Data],
			let data = lookup[key],
			let token = NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken {
			return token
		}
		return nil
	}

	private static func setDatabaseToken(_ token: CKServerChangeToken?, for database: CKDatabaseScope) {
		let key = database.keyName
		var lookup = PersistedOptions.defaults.object(forKey: "databaseTokens") as? [String : Data] ?? [String : Data]()
		if let n = token {
			lookup[key] = NSKeyedArchiver.archivedData(withRootObject: n)
		} else {
			lookup[key] = nil
		}
		PersistedOptions.defaults.set(lookup, forKey: "databaseTokens")
		PersistedOptions.defaults.synchronize()
	}

	static func wipeDatabaseTokens() {
		PersistedOptions.defaults.set([String: Data](), forKey: "databaseTokens")
		PersistedOptions.defaults.synchronize()
	}
}
