
import Foundation

extension Model {

	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {
		rebuildLabels()
	}

	static func startupComplete() {
		rebuildLabels()
	}

	static func startMonitoringForExternalChangesToBlobs() {
		syncWithExternalUpdates()

		
	}

	private static func syncWithExternalUpdates() {
		let changedDrops = drops.filter { $0.scanForBlobChanges() }
		for item in changedDrops {
			log("Located item whose data has been externally changed: \(item.uuid.uuidString)")
			item.needsReIngest = true
		}
		if !changedDrops.isEmpty {
			Model.save()
		}
	}

	static func saveComplete() {
		NotificationCenter.default.post(name: .SaveComplete, object: nil)
		if saveIsDueToSyncFetch {
			saveIsDueToSyncFetch = false
			log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
		} else {
			log("Will sync up after a local save")
			CloudManager.sync { error in
				if let error = error {
					log("Error in push after save: \(error.finalDescription)")
				}
			}
		}
	}

	static func saveIndexComplete() {}
}

extension ArchivedDropItem {
	func scanForBlobChanges() -> Bool {
		var someHaveChanged = false
		for component in typeItems { // intended: iterate over all over them, not just until the first one
			if component.scanForBlobChanges() {
				someHaveChanged = true
			}
		}
		return someHaveChanged
	}
}

extension ArchivedDropItemType {
	func scanForBlobChanges() -> Bool {
		let recordLocation = bytesPath
		if let blobModification = Model.modificationDate(for: recordLocation) { // blob exists?
			if let recordedModification = lastGladysBlobUpdate { // we've stamped this
				if recordedModification < blobModification { // is the file modified after we stamped it?
					lastGladysBlobUpdate = Date()
					return true
				}
			} else {
				lastGladysBlobUpdate = Date() // no stamp, migrate, add current date
			}
		}
		return false
	}

	var lastGladysBlobUpdate: Date? {
		get {
			let recordLocation = bytesPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				return recordLocation.withUnsafeFileSystemRepresentation { fileSystemPath in
					let length = getxattr(fileSystemPath, "build.bru.Gladys.lastGladysModification", nil, 0, 0, 0)
					if length > 0 {
						var data = Data(count: length)
						let result = data.withUnsafeMutableBytes {
							getxattr(fileSystemPath, "build.bru.Gladys.lastGladysModification", $0, length, 0, 0)
						}
						if result > 0, let dateString = String(data: data, encoding: .utf8), let time = TimeInterval(dateString) {
							return Date(timeIntervalSinceReferenceDate: time)
						}
					}
					return nil
				}
			}
			return nil
		}
		set {
			let recordLocation = bytesPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				return recordLocation.withUnsafeFileSystemRepresentation { fileSystemPath in
					if let data = String(Date().timeIntervalSinceReferenceDate).data(using: .utf8) {
						_ = data.withUnsafeBytes {
							setxattr(fileSystemPath, "build.bru.Gladys.lastGladysModification", $0, data.count, 0, 0)
						}
					}
				}
			}
		}
	}
}
