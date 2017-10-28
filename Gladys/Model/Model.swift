
import Foundation
#if MAINAPP || FILEPROVIDER
	import FileProvider
#endif

final class Model {

	static var drops = [ArchivedDropItem]()
	static var dataFileLastModified = Date.distantPast

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

	static func modificationDate(for url: URL) -> Date? {
		return (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
	}

	static func item(uuid: String) -> ArchivedDropItem? {
		let uuidData = UUID(uuidString: uuid)
		return drops.first { $0.uuid == uuidData }
	}

	static func typeItem(uuid: String) -> ArchivedDropItemType? {
		let uuidData = UUID(uuidString: uuid)
		return drops.flatMap({
			$0.typeItems.first { $0.uuid == uuidData }
		}).first
	}

	private static func loadData() {
		
		var coordinationError: NSError?
		// withoutChanges because we only signal the provider after we have saved
		coordinator.coordinate(readingItemAt: fileUrl, options: .withoutChanges, error: &coordinationError) { url in

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
						drops = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
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
	}

	private static var isStarted = false

	static func ensureStarted() {
		if isStarted { return }
		loadData()
		startupComplete()
	}

	static func reloadDataIfNeeded() {
		ensureStarted()
		loadData()
		DispatchQueue.main.async {
			reloadCompleted()
		}
	}
}

