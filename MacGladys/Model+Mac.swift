
import Foundation

extension Model {

	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {
		rebuildLabels()
	}

	static func startupComplete() {

		// cleanup, in case of previous crashes, cancelled transfers, etc

		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(at: appStorageUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else { return }
		let uuids = items.compactMap { UUID(uuidString: $0.lastPathComponent) }
		let nonExistingUUIDs = uuids.filter { uuid -> Bool in
			return !drops.contains { $0.uuid == uuid }
		}
		for uuid in nonExistingUUIDs {
			let url = appStorageUrl.appendingPathComponent(uuid.uuidString)
			try? fm.removeItem(at: url)
		}

		rebuildLabels()
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
}
