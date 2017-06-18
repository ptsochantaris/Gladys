
import Foundation

final class Model {

	var drops: [ArchivedDropItem]

	private let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .inherit, target: nil)

	lazy var saveTimer: PopTimer = {
		return PopTimer(timeInterval: 1.0) { [weak self] in
			guard let s = self else { return }

			let itemsToSave = s.drops.filter { !$0.isLoading }

			s.saveQueue.async {
				NSLog("Saving")

				do {
					let data = try JSONEncoder().encode(itemsToSave)
					try data.write(to: Model.fileUrl, options: .atomic)
				} catch {
					NSLog("Saving Error: \(error.localizedDescription)")
				}
			}
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
		Model.shared = self
	}

	private static var shared: Model!

	class func save() {
		shared.saveTimer.push()
	}
}

