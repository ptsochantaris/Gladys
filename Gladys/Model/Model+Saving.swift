import UIKit

extension Model {
	private static var needsAnotherSave = false
	private static var isSaving = false
	private static var nextSaveCallbacks: [()->Void]?

	static func queueNextSaveCallback(_ callback: @escaping ()->Void) {
		if nextSaveCallbacks == nil {
			nextSaveCallbacks = [()->Void]()
		}
		nextSaveCallbacks!.append(callback)
	}

	private static func performAnyNextSaveCallbacks() {
		if let n = nextSaveCallbacks {
			for callback in n {
				callback()
			}
			nextSaveCallbacks = nil
		}
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

	private static let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	private static func performSave() {

		let start = Date()

		let itemsToSave = drops.filter { $0.goodToSave }
		let uuidsToEncode = itemsToSave.flatMap { i -> UUID? in
			if i.needsSaving {
				i.needsSaving = false
				return i.uuid
			}
			return nil
		}

		isSaving = true
		needsAnotherSave = false

		saveQueue.async {

			do {
				log("\(itemsToSave.count) items to save, \(uuidsToEncode.count) items to encode")
				try self.coordinatedSave(allItems: itemsToSave, dirtyUuids: uuidsToEncode)
				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				log("Saving Error: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				if needsAnotherSave {
					performSave()
				} else {
					isSaving = false
					performAnyNextSaveCallbacks()
					saveComplete()
				}
			}
		}
	}

	private static func coordinatedSave(allItems: [ArchivedDropItem], dirtyUuids: [UUID]) throws {
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			do {
				let fm = FileManager.default
				if !fm.fileExists(atPath: itemsDirectoryUrl.path) {
					try fm.createDirectory(at: itemsDirectoryUrl, withIntermediateDirectories: true, attributes: nil)
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

				if let filesInDir = fm.enumerator(atPath: itemsDirectoryUrl.path)?.allObjects as? [String] {
					if (filesInDir.count - 1) > allItems.count { // old file exists, let's find it
						let uuidStrings = allItems.map { $0.uuid.uuidString }
						for file in filesInDir {
							if !uuidStrings.contains(file) && file != "uuids" { // old file
								log("Removing file for non-existent item: \(file)")
								try? fm.removeItem(atPath: itemsDirectoryUrl.appendingPathComponent(file).path)
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
			} catch {
				coordinationError = error as NSError
			}
		}
		if let e = coordinationError {
			throw e
		}
	}
}
