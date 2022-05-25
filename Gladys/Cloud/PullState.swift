import CloudKit
import GladysFramework

final class PullState {
	var updatedSequence = false
    var newDropCount = 0 { didSet { updateProgress() } }
	var newTypeItemCount = 0 { didSet { updateProgress() } }

	var typeUpdateCount = 0 { didSet { updateProgress() } }
	var deletionCount = 0 { didSet { updateProgress() } }
	var updateCount = 0 { didSet { updateProgress() } }
	var newTypesAppended = 0
	
	var updatedDatabaseTokens = [CKDatabase.Scope: CKServerChangeToken]()
	var updatedZoneTokens = [CKRecordZone.ID: CKServerChangeToken]()
	var pendingShareRecords = Set<CKShare>()
	var pendingTypeItemRecords = Set<CKRecord>()

	private func updateProgress() {
		var components = [String]()
		
		if newDropCount > 0 { components.append(newDropCount == 1 ? "1 Drop" : "\(newDropCount) Drops") }
        if updateCount > 0 { components.append(updateCount == 1 ? "1 Update" : "\(updateCount) Updates") }
		if newTypeItemCount > 0 { components.append(newTypeItemCount == 1 ? "1 Component" : "\(newTypeItemCount) Components") }
		if typeUpdateCount > 0 { components.append(typeUpdateCount == 1 ? "1 Component Update" : "\(typeUpdateCount) Component Updates") }
		if deletionCount > 0 { components.append(deletionCount == 1 ? "1 Deletion" : "\(deletionCount) Deletions") }
		
		if components.isEmpty {
            CloudManager.syncProgressString = "Fetching"
		} else {
            CloudManager.syncProgressString = "Fetched " + components.joined(separator: ", ")
		}
	}

    func processChanges(commitTokens: Bool) async {
		CloudManager.syncProgressString = "Updating…"
		log("Changes fetch complete, processing")

        if updatedSequence || newDropCount > 0 {
			let sequence = CloudManager.uuidSequence.compactMap { UUID(uuidString: $0) }
			if !sequence.isEmpty {
				Model.drops.sort { i1, i2 in
					let p1 = sequence.firstIndex(of: i1.uuid) ?? -1
					let p2 = sequence.firstIndex(of: i2.uuid) ?? -1
					return p1 < p2
				}
			}
		}
		
		let itemsModified = typeUpdateCount + newDropCount + updateCount + deletionCount + newTypesAppended > 0

		if itemsModified {
			// need to save stuff that's been modified
            let task = Task {
                await withCheckedContinuation { continuation in
                    Model.queueNextSaveCallback {
                        continuation.resume()
                    }
                }
            }
			Model.saveIsDueToSyncFetch = true
			Model.save()
            await task.value

		} else if !updatedZoneTokens.isEmpty {
			// a position record, most likely?
			if updatedSequence {
                Model.saveIsDueToSyncFetch = true
                Model.saveIndexOnly()
			}
            
		} else {
			log("No updates available")
		}
        
        if commitTokens {
            if !updatedZoneTokens.isEmpty || !updatedDatabaseTokens.isEmpty {
                log("Committing change tokens")
            }
            for (zoneId, zoneToken) in updatedZoneTokens {
                PullState.setZoneToken(zoneToken, for: zoneId)
            }
            for (databaseId, databaseToken) in updatedDatabaseTokens {
                PullState.setDatabaseToken(databaseToken, for: databaseId)
            }
        }
	}

	private static var legacyZoneChangeToken: CKServerChangeToken? {
		get {
			if let data = PersistedOptions.defaults.data(forKey: "zoneChangeToken"), !data.isEmpty {
                return SafeArchiving.unarchive(data) as? CKServerChangeToken
			} else {
				return nil
			}
		}
		set {
			if let n = newValue {
                if let data = SafeArchiving.archive(n) {
                    PersistedOptions.defaults.set(data, forKey: "zoneChangeToken")
                }
			} else {
				PersistedOptions.defaults.set(emptyData, forKey: "zoneChangeToken")
			}
		}
	}

	static func checkMigrations() {
		if let token = legacyZoneChangeToken {
			setZoneToken(token, for: privateZoneId)
			legacyZoneChangeToken = nil
		}
	}

	///////////////////////////////////////

    @UserDefault(key: "zoneTokens", defaultValue: [String: Data]())
    private static var zoneTokens: [String: Data]

	static func zoneToken(for zoneId: CKRecordZone.ID) -> CKServerChangeToken? {
		if let data = zoneTokens[zoneId.ownerName + ":" + zoneId.zoneName] {
            return SafeArchiving.unarchive(data) as? CKServerChangeToken
		}
		return nil
	}

	static func setZoneToken(_ token: CKServerChangeToken?, for zoneId: CKRecordZone.ID) {
		let key = zoneId.ownerName + ":" + zoneId.zoneName
		if let n = token {
			zoneTokens[key] = SafeArchiving.archive(n)
		} else {
            zoneTokens[key] = nil
		}
	}

	static func wipeZoneTokens() {
        zoneTokens = [String: Data]()
		legacyZoneChangeToken = nil
	}

	///////////////////////////////////////

    @UserDefault(key: "databaseTokens", defaultValue: [String: Data]())
    private static var databaseTokens: [String: Data]

	static func databaseToken(for database: CKDatabase.Scope) -> CKServerChangeToken? {
		if let data = databaseTokens[database.keyName] {
            return SafeArchiving.unarchive(data) as? CKServerChangeToken
		}
		return nil
	}

	private static func setDatabaseToken(_ token: CKServerChangeToken?, for database: CKDatabase.Scope) {
		if let n = token {
            databaseTokens[database.keyName] = SafeArchiving.archive(n)
		} else {
            databaseTokens[database.keyName] = nil
		}
	}

	static func wipeDatabaseTokens() {
        databaseTokens = [String: Data]()
	}
}
