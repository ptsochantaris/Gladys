import UIKit

extension Model {
	private static var isSaving = false
	static var needsAnotherSave = false
	static var oneTimeSaveCallback: (()->Void)?

	func save() {
		assert(Thread.isMainThread)
		if Model.isSaving {
			Model.needsAnotherSave = true
		} else {
			_save()
		}
	}

	private static let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	private func _save() {

		let start = Date()

		let itemsToSave = drops.filter { $0.loadingProgress == nil && !$0.isDeleting }

		prepareToSave()

		Model.isSaving = true
		Model.needsAnotherSave = false

		Model.saveQueue.async {

			do {
				let data = try JSONEncoder().encode(itemsToSave)
				self.coordinatedSave(data: data)
				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				log("Saving Error: \(error.localizedDescription)")
			}
			DispatchQueue.main.async {
				if Model.needsAnotherSave {
					self._save()
				} else {
					Model.isSaving = false
					self.saveComplete()
					Model.oneTimeSaveCallback?()
					Model.oneTimeSaveCallback = nil
				}
				self.saveDone()
			}
		}
	}

	private func coordinatedSave(data: Data) {
		var coordinationError: NSError?
		Model.coordinator.coordinate(writingItemAt: Model.fileUrl, options: [], error: &coordinationError) { url in
			try! data.write(to: url, options: [])
			if let dataModified = Model.modificationDate(for: url) {
				dataFileLastModified = dataModified
			}
		}
		if let e = coordinationError {
			log("Error in saving coordination: \(e.localizedDescription)")
		}
	}
}
