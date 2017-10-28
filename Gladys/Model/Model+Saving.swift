import UIKit

extension Model {
	private static var isSaving = false
	static var needsAnotherSave = false
	static var oneTimeSaveCallback: (()->Void)?

	static func save() {
		assert(Thread.isMainThread)
		if isSaving {
			needsAnotherSave = true
		} else {
			_save()
		}
	}

	private static let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	private static func _save() {

		let start = Date()

		let itemsToSave = drops.filter { $0.loadingProgress == nil && !$0.isDeleting }

		prepareToSave()

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
					self._save()
				} else {
					isSaving = false
					self.saveComplete()
					oneTimeSaveCallback?()
					oneTimeSaveCallback = nil
				}
				self.saveDone()
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
