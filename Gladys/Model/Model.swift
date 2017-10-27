
import Foundation
#if MAINAPP || FILEPROVIDER
	import FileProvider
#endif

let model = Model()

final class Model: NSObject {

	var drops: [ArchivedDropItem]
	var dataFileLastModified = Date.distantPast

	static var appStorageUrl: URL = {
		#if MAINAPP || FILEPROVIDER
			return NSFileProviderManager.default.documentStorageURL
		#else
			return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.build.bru.Gladys")!.appendingPathComponent("File Provider Storage")
		#endif
	}()

	static var fileUrl: URL = {
		return appStorageUrl.appendingPathComponent("items.json")
	}()

	override init() {
		drops = Model.loadData(&dataFileLastModified) ?? [ArchivedDropItem]()
		super.init()
		startupComplete()
	}

	static func modificationDate(for url: URL) -> Date? {
		return (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
	}

	func item(uuid: String) -> ArchivedDropItem? {
		let uuidData = UUID(uuidString: uuid)
		return drops.first { $0.uuid == uuidData }
	}

	func typeItem(uuid: String) -> ArchivedDropItemType? {
		let uuidData = UUID(uuidString: uuid)
		return drops.flatMap({
			$0.typeItems.first { $0.uuid == uuidData }
		}).first
	}

	private static func loadData(_ dataFileLastModified: inout Date) -> [ArchivedDropItem]? {
		
		var res: [ArchivedDropItem]?

		var coordinationError: NSError?
		// withoutChanges because we only signal the provider after we have saved
		coordinator.coordinate(readingItemAt: Model.fileUrl, options: .withoutChanges, error: &coordinationError) { url in

			if FileManager.default.fileExists(atPath: url.path) {
				do {

					var shouldLoad = true
					if let dataModified = modificationDate(for: url) {
						if dataModified == dataFileLastModified {
							shouldLoad = false
						} else {
							dataFileLastModified = dataModified
						}
					}
					if shouldLoad {
						log("Needed to reload data, new file date: \(dataFileLastModified)")
						let data = try Data(contentsOf: url, options: [.alwaysMapped])
						res = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
					}
				} catch {
					log("Loading Error: \(error)")
				}
			} else {
				log("Starting fresh store")
			}
		}
		if let e = coordinationError {
			log("Error in loading coordination: \(e.localizedDescription)")
			abort()
		}
		return res
	}

	func reloadDataIfNeeded() {
		if let d = Model.loadData(&dataFileLastModified) {
			drops = d
			DispatchQueue.main.async {
				self.reloadCompleted()
			}
		}
	}
}

