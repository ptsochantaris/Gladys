
import Foundation

final class Model {

	var drops: [ArchivedDropItem]

	private let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .inherit, target: nil)

	lazy var saveTimer: PopTimer = {
		return PopTimer(timeInterval: 1.0) { [weak self] in
			self?.save(immediately: true)
		}
	}()

	static var fileUrl: URL {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		return docs.appendingPathComponent("items.json")
	}

	init() {
		let url = Model.fileUrl
		if FileManager.default.fileExists(atPath: url.path) {
			do {
				let data = try Data(contentsOf: url)
				drops = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
			} catch {
				NSLog("Loading Error: \(error)")
				drops = [ArchivedDropItem]()
			}
		} else {
			NSLog("Starting fresh store")
			drops = [ArchivedDropItem]()
		}
	}

	func save(immediately: Bool = false) {
		if !immediately {
			saveTimer.push()
			return
		}

		saveTimer.abort()

		let itemsToSave = drops.filter { !$0.isLoading }

		saveQueue.async {
			NSLog("Saving")

			do {
				let data = try JSONEncoder().encode(itemsToSave)
				try data.write(to: Model.fileUrl, options: .atomic)
			} catch {
				NSLog("Saving Error: \(error.localizedDescription)")
			}
		}

	}
}

