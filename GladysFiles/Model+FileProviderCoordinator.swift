
import FileProvider

extension Model {

	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	static func prepareToSave() {}
	static func saveComplete() {}
	static func saveIndexComplete() {}
	static func startupComplete() {}
	static func reloadCompleted() {}

	static func coordinatedCommit(item: ArchivedDropItem) {
		if brokenMode {
			log("Ignoring save, model is broken, app needs restart.")
			return
		}
		if legacyMode {
			log("Ignoring save, model is in legacy mode.")
			return
		}
		var closureError: NSError?
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			let u = item.uuid
			log("Comitting just data for \(u)")
			do {
				try JSONEncoder().encode(item).write(to: url.appendingPathComponent(u.uuidString), options: .atomic)
				if let dataModified = modificationDate(for: url) {
					dataFileLastModified = dataModified
				}

			} catch {
				closureError = error as NSError
			}
		}
		if let e = coordinationError ?? closureError {
			log("Saving item failed: \(e.localizedDescription)")
		}
	}
}
