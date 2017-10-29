import UIKit

extension Model {
	static var needsAnotherSave = false
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

		let itemsToSave = drops.filter { $0.loadingProgress == nil && !$0.isDeleting }

		isSaving = true
		needsAnotherSave = false

		saveQueue.async {

			do {
				let data = try JSONEncoder().encode(itemsToSave)
				self.coordinatedSave(data: data)
				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				log("Saving Error: \(error.localizedDescription)")
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

	private static func coordinatedSave(data: Data) {
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: fileUrl, options: [], error: &coordinationError) { url in
			try! data.write(to: url, options: [])
			if let dataModified = modificationDate(for: url) {
				dataFileLastModified = dataModified
			}
		}
		if let e = coordinationError {
			log("Error in saving coordination: \(e.localizedDescription)")
		}
	}
}
