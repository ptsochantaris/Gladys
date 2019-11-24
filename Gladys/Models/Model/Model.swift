
import Foundation

final class Model {

	static var brokenMode = false
	static var drops = [ArchivedDropItem]()
	static var dataFileLastModified = Date.distantPast

	private static var isStarted = false

	static func reset() {
		drops.removeAll(keepingCapacity: false)
		clearCaches()
		dataFileLastModified = .distantPast
	}

	static func reloadDataIfNeeded(maximumItems: Int? = nil) {

		if brokenMode {
			log("Ignoring load, model is broken, app needs restart.")
			return
		}

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
					let totalItemsInStore = d.count / 16
					let itemCount: Int
					if let maximumItems = maximumItems {
						itemCount = min(maximumItems, totalItemsInStore)
					} else {
						itemCount = totalItemsInStore
					}
					var newDrops = [ArchivedDropItem]()
					newDrops.reserveCapacity(itemCount)
					var c = 0
					let decoder = JSONDecoder()
					while c < d.count {
						let u = UUID(uuid: (d[c], d[c+1], d[c+2], d[c+3], d[c+4], d[c+5],
											d[c+6], d[c+7], d[c+8], d[c+9], d[c+10], d[c+11],
											d[c+12], d[c+13], d[c+14], d[c+15]))
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
			brokenMode = true
			log("Error in loading: \(e)")
			#if MAINAPP || MAC
			if let underlyingError = e.userInfo[NSUnderlyingErrorKey] as? NSError {
				e = underlyingError
			}
			DispatchQueue.main.async {
				genericAlert(title: "Loading Error (code \(e.code))",
					message: "This app's data store is not yet accessible. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(e.domain): \(e.localizedDescription)\n\nIf this error persists, please report it to the developer.",
				buttonTitle: "Quit") {
					abort()
				}
			}
			return
			#else
			// still boot the item, so it doesn't block others, but keep blank contents and abort after a second or two
			DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
				exit(0)
			}
			#endif
			
		} else if var e = coordinationError {
			log("Error in file coordinator: \(e)")
			#if MAINAPP || MAC
			if let underlyingError = e.userInfo[NSUnderlyingErrorKey] as? NSError {
				e = underlyingError
			}
			DispatchQueue.main.async {
				genericAlert(title: "Loading Error (code \(e.code))",
					message: "Could not communicate with an extension. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(e.domain): \(e.localizedDescription)\n\nIf this error persists, please report it to the developer.",
				buttonTitle: "Quit") {
					abort()
				}
			}
			return
			#else
			exit(0)
			#endif
		}

		if !brokenMode {
			DispatchQueue.main.async {
				if isStarted {
					if didLoad {
                        NotificationCenter.default.post(name: .ModelDataUpdated, object: nil)
					}
				} else {
					isStarted = true
					startupComplete()
				}
			}
		}
	}

	static var visibleDrops: [ArchivedDropItem] {
		return drops.filter { $0.isVisible }
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
		return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
	}

	static let appStorageUrl: URL = {
		let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
		#if MAC
		log("Model URL: \(url.path)")
		return url
		#else
		let fps = url.appendingPathComponent("File Provider Storage")
		log("Model URL: \(fps.path)")
		return fps
		#endif
	}()
}

