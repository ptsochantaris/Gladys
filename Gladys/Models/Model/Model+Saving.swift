import Foundation

extension Model {

	private static let saveQueue = DispatchQueue(label: "build.bru.Gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)
	private static var needsAnotherSave = false
	private static var isSaving = false
	private static var nextSaveCallbacks: [()->Void]?

	static func queueNextSaveCallback(_ callback: @escaping ()->Void) {
		if nextSaveCallbacks == nil {
			nextSaveCallbacks = [()->Void]()
		}
		nextSaveCallbacks!.append(callback)
	}

	static func save() {
		assert(Thread.isMainThread)

		if isSaving {
			needsAnotherSave = true
		} else {
			prepareToSave()
			performSave()
		}
	}

	private static func performSave() {

		let itemsToSave = drops.filter { $0.goodToSave }
		let uuidsToEncode = itemsToSave.compactMap { i -> UUID? in
			if i.needsSaving {
				i.needsSaving = false
				i.isBeingCreatedBySync = false
				return i.uuid
			}
			return nil
		}

		isSaving = true
		needsAnotherSave = false

		saveQueue.async {
			do {
				try self.coordinatedSave(allItems: itemsToSave, dirtyUuids: uuidsToEncode)
			} catch {
				log("Saving Error: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				if needsAnotherSave {
					performSave()
				} else {
					isSaving = false
					if let n = nextSaveCallbacks {
						for callback in n {
							callback()
						}
						nextSaveCallbacks = nil
					}
					saveComplete()
				}
			}
		}
	}
	
	static func saveIndexOnly() {
		let itemsToSave = drops.filter { $0.goodToSave }
		saveQueue.async {
			do {
				try coordinatedSave(allItems: itemsToSave, dirtyUuids: [])
				log("Saved index only")
			} catch {
				log("Warning: Error while committing index to disk: (\(error.finalDescription))")
			}
			DispatchQueue.main.async {
				saveIndexComplete()
			}
		}
	}

	static func commitItem(item: ArchivedDropItem) {
		let itemsToSave = drops.filter { $0.goodToSave }
		item.isBeingCreatedBySync = false
		item.needsSaving = false
		let uuid = item.uuid
		saveQueue.async {
			if item.isDeleting {
				log("Skipping save of item \(uuid) as it's marked for deletion")
				return
			}
			do {
				try coordinatedSave(allItems: itemsToSave, dirtyUuids: [uuid])
				log("Ingest completed for item (\(uuid)) and committed to disk")
			} catch {
				log("Warning: Error while committing item to disk: (\(error.finalDescription))")
			}
		}
	}

	private static func coordinatedSave(allItems: [ArchivedDropItem], dirtyUuids: [UUID]) throws {
		if brokenMode {
			log("Ignoring save, model is broken, app needs restart.")
			return
		}
		var closureError: NSError?
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			let start = Date()
			log("Saving: \(allItems.count) uuids, \(dirtyUuids.count) updated data files")
			do {
				let fm = FileManager.default
				if !fm.fileExists(atPath: url.path) {
					try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
				}

				let e = dirtyUuids.count > 0 ? JSONEncoder() : nil

				var uuidData = Data()
				uuidData.reserveCapacity(allItems.count * 16)
				for item in allItems {
					let u = item.uuid
					let t = u.uuid
					uuidData.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
					if let e = e, dirtyUuids.contains(u) {
						try autoreleasepool {
							try e.encode(item).write(to: url.appendingPathComponent(u.uuidString), options: .atomic)
						}
					}
				}
				try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

				if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String] {
					if (filesInDir.count - 1) > allItems.count { // old file exists, let's find it
						let uuidStrings = allItems.map { $0.uuid.uuidString }
						for file in filesInDir {
							if !uuidStrings.contains(file) && file != "uuids" { // old file
								log("Removing save file for non-existent item: \(file)")
								try? fm.removeItem(atPath: url.appendingPathComponent(file).path)
							}
						}
					}
				}

				if fm.fileExists(atPath: legacyFileUrl.path) {
					try? fm.removeItem(at: legacyFileUrl)
				}

				if let dataModified = modificationDate(for: url) {
					dataFileLastModified = dataModified
				}

				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				closureError = error as NSError
			}
		}
		if let e = coordinationError ?? closureError {
			throw e
		}
	}
}
