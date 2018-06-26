
import Foundation

final class Model {

	static var legacyFileLastModified = Date.distantPast
	static var legacyMode = true

	static let legacyFileUrl: URL = {
		return appStorageUrl.appendingPathComponent("items.json", isDirectory: false)
	}()

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

		legacyMode = false

		var coordinationError: NSError?
		var loadingError : NSError?
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
					} else {
						log("No need to reload data")
					}
				} catch {
					log("Loading Error: \(error)")
					loadingError = error as NSError
				}
			} else {
				drops = []
				log("Starting fresh store")
			}
		}

		if let e = coordinationError ?? loadingError {
			log("Error in loading coordination: \(e.finalDescription)")
			#if MAINAPP || MAC
			DispatchQueue.main.async {
				genericAlert(title: "Loading Error (Code: \(e.code))", message: "This app's data store seems corrupt. The message received from the OS is:\n\n\"\(e.localizedDescription)\".\n\nPlease report this to the developer.") {
					abort()
				}
			}
			return
			#else
			abort()
			#endif
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
			drops = []
			legacyMode = false
			log("Starting fresh store")
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
					legacyMode = true

					let data = try Data(contentsOf: legacyFileUrl, options: [.alwaysMapped])
					drops = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
				} else {
					log("LEGACY: No need to reload data")
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

	static var visibleDrops: [ArchivedDropItem] {
		if Model.legacyMode {
			return []
		}
		return drops.filter { !$0.needsDeletion && $0.lockPassword == nil }
	}
}

