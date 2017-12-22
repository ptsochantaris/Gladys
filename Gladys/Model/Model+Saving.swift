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
		let itemsToEncode = itemsToSave.filter { $0.needsSaving }
		for item in itemsToEncode {
			item.needsSaving = false
		}
		log("\(itemsToSave.count) items to save, \(itemsToEncode.count) items to encode")

		isSaving = true
		needsAnotherSave = false

		saveQueue.async {

			do {
				try self.coordinatedSave(allItems: itemsToSave, dirtyItems: itemsToEncode)
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

	private static func coordinatedSave(allItems: [ArchivedDropItem], dirtyItems: [ArchivedDropItem]) throws {
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			do {
				let fm = FileManager.default
				if !fm.fileExists(atPath: itemsDirectoryUrl.path) {
					try fm.createDirectory(at: itemsDirectoryUrl, withIntermediateDirectories: true, attributes: nil)
				}

				let uuids = allItems.map { $0.uuid }
				let e = JSONEncoder()
				try e.encode(uuids).write(to: url.appendingPathComponent("uuids"), options: [.atomic])
				for item in dirtyItems {
					try e.encode(item).write(to: url.appendingPathComponent(item.uuid.uuidString), options: [.atomic])
				}

				if let filesInDir = fm.enumerator(atPath: itemsDirectoryUrl.path)?.allObjects as? [String] {
					if (filesInDir.count - 1) > uuids.count { // old file exists, let's find it
						let uuidStrings = uuids.map { $0.uuidString }
						for file in filesInDir {
							if !uuidStrings.contains(file) && file != "uuids" { // old file
								log("Removing file for non-existent item: \(file)")
								try? fm.removeItem(atPath: itemsDirectoryUrl.appendingPathComponent(file).path)
							}
						}
					}
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
