import CloudKit

class SyncState {
	var updatedSequence = false
	var newDrops = [CKRecord]() { didSet { updateProgress() } }
	var newTypeItemsToHookOntoDrops = [CKRecord]() { didSet { updateProgress() } }
	
	var typeUpdateCount = 0 { didSet { updateProgress() } }
	var deletionCount = 0 { didSet { updateProgress() } }
	var updateCount = 0 { didSet { updateProgress() } }
	var newTypesAppended = 0
	
	var updatedDatabaseTokens = [Int : CKServerChangeToken]()
	var updatedZoneTokens = [CKRecordZoneID : CKServerChangeToken]()

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
			CloudManager.syncProgressString = "Fetched " + components.joined(separator: ", ")
		} else {
			CloudManager.syncProgressString = "Fetching"
		}
	}

	private func createNewArchivedDrop(from record: CKRecord, drawChildrenFrom: [CKRecord]) {
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
	
	func commitChanges() {
		CloudManager.syncProgressString = "Applying updates"
		log("Changes fetch complete, processing")
		
		for newTypeItemRecord in newTypeItemsToHookOntoDrops {
			if let parentId = (newTypeItemRecord["parent"] as? CKReference)?.recordID.recordName, let existingParent = Model.item(uuid: parentId) {
				let newTypeItem = ArchivedDropItemType(from: newTypeItemRecord, parentUuid: existingParent.uuid)
				existingParent.typeItems.append(newTypeItem)
				existingParent.needsReIngest = true
				newTypesAppended += 1
			}
		}
		for dropRecord in newDrops {
			createNewArchivedDrop(from: dropRecord, drawChildrenFrom: newTypeItemsToHookOntoDrops)
		}
		
		if updatedSequence || newDrops.count > 0 {
			let sequence = CloudManager.uuidSequence.compactMap { UUID(uuidString: $0) }
			if sequence.count > 0 {
				Model.drops.sort { i1, i2 in
					let p1 = sequence.index(of: i1.uuid) ?? -1
					let p2 = sequence.index(of: i2.uuid) ?? -1
					return p1 < p2
				}
			}
		}
		
		let itemsModified = typeUpdateCount + newDrops.count + updateCount + deletionCount + newTypesAppended > 0

		if itemsModified || updatedSequence {
			log("Posting external data update notification")
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
		}
		
		if itemsModified {
			// need to save stuff that's been modified
			Model.queueNextSaveCallback {
				self.commitNewZoneTokens()
			}
			Model.saveIsDueToSyncFetch = true
			Model.save()
		} else if !updatedZoneTokens.isEmpty {
			// a position record, most likely?
			if updatedSequence {
				Model.saveIndexOnly()
			}
			commitNewZoneTokens()
		} else {
			log("No updates available")
			commitNewZoneTokens()
		}
	}

	private func commitNewZoneTokens() {
		if updatedZoneTokens.count > 0 || updatedDatabaseTokens.count > 0 {
			log("Comitting change tokens")
		}
		for (zoneId, zoneToken) in updatedZoneTokens {
			SyncState.setZoneToken(zoneToken, for: zoneId)
		}
		for (databaseId, databaseToken) in updatedDatabaseTokens {
			SyncState.setDatabaseToken(databaseToken, for: databaseId)
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
			setZoneToken(token, for: CloudManager.legacyZoneId)
			legacyZoneChangeToken = nil
		}
	}

	///////////////////////////////////////

	static func zoneToken(for zoneId: CKRecordZoneID) -> CKServerChangeToken? {
		if let lookup = PersistedOptions.defaults.value(forKey: "zoneTokens") as? [String : Data],
			let data = lookup[zoneId.ownerName + ":" + zoneId.zoneName],
			let token = NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken {
			return token
		}

		return nil
	}

	static func setZoneToken(_ token: CKServerChangeToken?, for zoneId: CKRecordZoneID) {
		var lookup = PersistedOptions.defaults.value(forKey: "zoneTokens") as? [String : Data] ?? [String : Data]()
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
		PersistedOptions.defaults.removeObject(forKey: "zoneTokens")
		PersistedOptions.defaults.synchronize()
		legacyZoneChangeToken = nil
	}

	///////////////////////////////////////

	static func databaseToken(for database: Int) -> CKServerChangeToken? {
		let key = String(database)
		if let lookup = PersistedOptions.defaults.value(forKey: "databaseTokens") as? [String : Data],
			let data = lookup[key],
			let token = NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken {
			return token
		}
		return nil
	}

	static func setDatabaseToken(_ token: CKServerChangeToken?, for database: Int) {
		let key = String(database)
		var lookup = PersistedOptions.defaults.value(forKey: "databaseTokens") as? [String : Data] ?? [String : Data]()
		if let n = token {
			lookup[key] = NSKeyedArchiver.archivedData(withRootObject: n)
		} else {
			lookup[key] = nil
		}
		PersistedOptions.defaults.set(lookup, forKey: "databaseTokens")
		PersistedOptions.defaults.synchronize()
	}

	static func wipeDatabaseTokens() {
		PersistedOptions.defaults.removeObject(forKey: "databaseTokens")
		PersistedOptions.defaults.synchronize()
	}
}
