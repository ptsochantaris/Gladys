
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
		trimTemporaryDirectory()
	}

	private static var eventMonitor: FileMonitor?
	static func startMonitoringForExternalChangesToBlobs() {
		syncWithExternalUpdates()

        eventMonitor = FileMonitor(directory: appStorageUrl) { url in
            let components = url.pathComponents
			let count = components.count

			guard count > 3, components[count-4].hasSuffix(".MacGladys"),
				let potentialParentUUID = UUID(uuidString: String(components[count-3])),
				let potentialComponentUUID = UUID(uuidString: String(components[count-2]))
				else { return }

			log("Examining potential external update for component \(potentialComponentUUID)")
			if let parent = item(uuid: potentialParentUUID), parent.eligibleForExternalUpdateCheck, let component = parent.typeItems.first(where: { $0.uuid == potentialComponentUUID}), component.scanForBlobChanges() {
				parent.needsReIngest = true
				parent.markUpdated()
                log("Detected a modified component blob, uuid \(potentialComponentUUID)")
				parent.reIngest(delegate: ViewController.shared)
			}
		}
	}

	private static func syncWithExternalUpdates() {
		let changedDrops = drops.filter { $0.scanForBlobChanges() }
		for item in changedDrops {
			log("Located item whose data has been externally changed: \(item.uuid.uuidString)")
			item.needsReIngest = true
			item.markUpdated()
			item.reIngest(delegate: ViewController.shared)
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
