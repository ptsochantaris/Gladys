
import Foundation
#if os(iOS)
import FileProvider
#endif

final class Model {

	private static var legacyFileLastModified = Date.distantPast
	static var legacyMode = true

	static var drops = [ArchivedDropItem]()
	static var dataFileLastModified = Date.distantPast

	private static var isStarted = false

	static let legacyFileUrl: URL = {
		return appStorageUrl.appendingPathComponent("items.json", isDirectory: false)
	}()

	static func reset() {
		drops.removeAll(keepingCapacity: false)
		clearCaches()
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

			if !FileManager.default.fileExists(atPath: url.path) {
				drops = []
				log("Starting fresh store")
				return
			}

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
		}

		if var e = loadingError {
			log("Error in loading: \(e)")
			#if MAINAPP || MAC
			if let underlyingError = e.userInfo[NSUnderlyingErrorKey] as? NSError {
				e = underlyingError
			}
			DispatchQueue.main.async {
				genericAlert(title: "Loading Error (Code: \(e.code))",
				message: "This app's data store is not accessible. The message from the OS is:\n\n\(e.localizedDescription) - \(itemsDirectoryUrl.path)\n\nIf you keep getting this error, please try restarting your device, as some data may be locked by iOS.\n\nIf this error persists, please report it to the developer.") {
					abort()
				}
			}
			return
			#else
			abort()
			#endif
			
		} else if var e = coordinationError {
			log("Error in file coordinator: \(e)")
			#if MAINAPP || MAC
			if let underlyingError = e.userInfo[NSUnderlyingErrorKey] as? NSError {
				e = underlyingError
			}
			DispatchQueue.main.async {
				genericAlert(title: "Loading Error (Code: \(e.code))",
				message: "Could not communicate with an extension. The message from the OS is:\n\n\(e.localizedDescription)\n\nIf you keep getting this error, please try restarting your device, as iOS may not have finished updating some Gladys components yet.\n\nIf this error persists, please report it to the developer.") {
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

	static let itemsDirectoryUrl: URL = {
		return appStorageUrl.appendingPathComponent("items", isDirectory: true)
	}()

	static let temporaryDirectoryUrl: URL = {
		let url = appStorageUrl.appendingPathComponent("temporary", isDirectory: true)
		let fm = FileManager.default
		if fm.fileExists(atPath: url.path) {
			try? fm.removeItem(at: url)
		}
		try! fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		return url
	}()

	static func item(uuid: String) -> ArchivedDropItem? {
		let uuidData = UUID(uuidString: uuid)
		return drops.first { $0.uuid == uuidData }
	}

	static func item(uuid: UUID) -> ArchivedDropItem? {
		return drops.first { $0.uuid == uuid }
	}

	static func item(shareId: String) -> ArchivedDropItem? {
		return drops.first { $0.cloudKitRecord?.share?.recordID.recordName == shareId }
	}

	static func typeItem(uuid: String) -> ArchivedDropItemType? {
		let uuidData = UUID(uuidString: uuid)
		return drops.compactMap { $0.typeItems.first { $0.uuid == uuidData } }.first
	}

	static func modificationDate(for url: URL) -> Date? {
		return (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
	}

	static let appStorageUrl: URL = {
		#if MAC
		return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
		#elseif MAINAPP || FILEPROVIDER
		return NSFileProviderManager.default.documentStorageURL
		#else
		return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!.appendingPathComponent("File Provider Storage")
		#endif
	}()
}

