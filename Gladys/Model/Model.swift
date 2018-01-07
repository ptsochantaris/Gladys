
import Foundation
#if MAINAPP || FILEPROVIDER
	import FileProvider
#endif

final class Model {

	static var drops = [ArchivedDropItem]()
	static var dataFileLastModified = Date.distantPast
	static var legacyFileLastModified = Date.distantPast

	static var appStorageUrl: URL = {
		#if MAINAPP || FILEPROVIDER
			return NSFileProviderManager.default.documentStorageURL
		#else
			return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.build.bru.Gladys")!.appendingPathComponent("File Provider Storage")
		#endif
	}()

	static var itemsDirectoryUrl: URL = {
		return appStorageUrl.appendingPathComponent("items", isDirectory: true)
	}()

	static var legacyFileUrl: URL = {
		return appStorageUrl.appendingPathComponent("items.json", isDirectory: false)
	}()

	static func modificationDate(for url: URL) -> Date? {
		return (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
	}

	static func item(uuid: String) -> ArchivedDropItem? {
		let uuidData = UUID(uuidString: uuid)
		return drops.first { $0.uuid == uuidData }
	}

	static func item(uuid: UUID) -> ArchivedDropItem? {
		return drops.first { $0.uuid == uuid }
	}

	static func typeItem(uuid: String) -> ArchivedDropItemType? {
		let uuidData = UUID(uuidString: uuid)
		return drops.flatMap({
			$0.typeItems.first { $0.uuid == uuidData }
		}).first
	}

	private static var isStarted = false

	static func reset() {
		drops.removeAll(keepingCapacity: false)
		dataFileLastModified = .distantPast
		legacyFileLastModified = .distantPast
	}

	static func reloadDataIfNeeded() {
		let fm = FileManager.default
		if fm.fileExists(atPath: itemsDirectoryUrl.path) {
			load()
		} else {
			legacyLoad()
		}
	}

	static private func load() {
		var coordinationError: NSError?
		var didLoad = false

		// withoutChanges because we only signal the provider after we have saved
		coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

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
						didLoad = true

						let start = Date()

						let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
						let itemCount = d.count / 16
						var newDrops = [ArchivedDropItem]()
						newDrops.reserveCapacity(itemCount)
						var c = 0
						let decoder = JSONDecoder()
						while c < d.count {
							let d0 = d[c]; let d1 = d[c+1]; let d2 = d[c+2]; let d3 = d[c+3]
							let d4 = d[c+4]; let d5 = d[c+5]; let d6 = d[c+6]; let d7 = d[c+7]
							let d8 = d[c+8]; let d9 = d[c+9]; let d10 = d[c+10]; let d11 = d[c+11]
							let d12 = d[c+12]; let d13 = d[c+13]; let d14 = d[c+14]; let d15 = d[c+15]
							let u = UUID(uuid: (d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15))
							c += 16
							let dataPath = url.appendingPathComponent(u.uuidString)
							if let data = try? Data(contentsOf: dataPath), let item = try? decoder.decode(ArchivedDropItem.self, from: data) {
								newDrops.append(item)
							}
						}
						drops = newDrops
						log("Load time: \(-start.timeIntervalSinceNow) seconds")
					}
				} catch {
					log("Loading Error: \(error)")
				}
			} else {
				log("Starting fresh store")
			}
		}
		if let e = coordinationError {
			log("Error in loading coordination: \(e.finalDescription)")
			abort()
		}

		DispatchQueue.main.async {
			if isStarted {
				if didLoad {
					reloadCompleted()
				}
			} else {
				isStarted = true
				startupComplete()
			}
		}
	}

	static private func legacyLoad() {
		var didLoad = false

		if !FileManager.default.fileExists(atPath: legacyFileUrl.path) {
			log("LEGACY: Starting fresh store")
		} else {
			do {
				var shouldLoad = true
				if let dataModified = modificationDate(for: legacyFileUrl) {
					if dataModified == legacyFileLastModified {
						shouldLoad = false
					} else {
						legacyFileLastModified = dataModified
					}
				}
				if shouldLoad {
					log("LEGACY: Needed to reload data, new file date: \(legacyFileLastModified)")
					didLoad = true

					let data = try Data(contentsOf: legacyFileUrl, options: [.alwaysMapped])
					drops = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
					for item in drops {
						item.needsSaving = true
					}
				}
			} catch {
				log("Error in legacy load: \(error.finalDescription)")
				abort()
			}
		}

		DispatchQueue.main.async {
			if isStarted {
				if didLoad {
					reloadCompleted()
				}
			} else {
				isStarted = true
				startupComplete()
			}
		}
	}
}

