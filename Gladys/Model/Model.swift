
import Foundation
import CoreSpotlight

final class Model: NSObject, CSSearchableIndexDelegate {

	var drops: [ArchivedDropItem]

	private let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .inherit, target: nil)

	static var fileUrl: URL {
		let docs = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.build.bru.Gladys")!
		return docs.appendingPathComponent("items.json")
	}

	override init() {
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
		super.init()
	}

	

	func save(completion: ((Bool)->Void)? = nil) {

		let itemsToSave = drops.filter { !$0.isLoading }

		saveQueue.async {
			NSLog("Saving")

			do {
				let data = try JSONEncoder().encode(itemsToSave)
				try data.write(to: Model.fileUrl, options: .atomic)
				DispatchQueue.main.async {
					completion?(true)
				}
			} catch {
				NSLog("Saving Error: \(error.localizedDescription)")
				DispatchQueue.main.async {
					completion?(true)
				}
			}
		}
	}

	//////////////////

	func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
		acknowledgementHandler()
	}

	func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
		acknowledgementHandler()
	}

	func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
		let model = Model()
		if let item = model.drops.filter({ $0.uuid.uuidString == itemIdentifier }).first,
			let data = item.bytes(for: typeIdentifier) {

			return data
		}
		return Data()
	}

	func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
		let model = Model()
		if let item = model.drops.filter({ $0.uuid.uuidString == itemIdentifier }).first,
			let url = item.url(for: typeIdentifier) {
			return url as URL
		}
		return URL(string:"file://")!
	}

}

