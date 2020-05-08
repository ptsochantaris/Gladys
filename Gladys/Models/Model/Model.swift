import Foundation

final class DropArray {
    
    private var uuidindex: [UUID: Int]?
    
    var all: ContiguousArray<ArchivedItem>
            
    var isEmpty: Bool {
        return all.isEmpty
    }
    
    var count: Int {
        return all.count
    }
    
    func append(_ newElement: ArchivedItem) {
        uuidindex = nil
        all.append(newElement)
    }
    
    func replaceItem(at index: Int, with item: ArchivedItem) {
        uuidindex = nil
        all[index] = item
    }
    
    private func rebuildIndexIfNeeded() {
        if uuidindex == nil {
            var count = -1
            uuidindex = Dictionary(uniqueKeysWithValues: all.map { count += 1; return ($0.uuid, count) })
            log("Rebuilt drop index")
        }
    }
    
    func firstIndexOfItem(with uuid: UUID) -> Int? {
        rebuildIndexIfNeeded()
        return uuidindex?[uuid]
    }

    func firstItem(with uuid: UUID) -> ArchivedItem? {
        if let i = firstIndexOfItem(with: uuid) {
            return all[i]
        }
        return nil
    }
    
    func firstIndexOfItem(with uuid: String) -> Int? {
        if let uuidData = UUID(uuidString: uuid) {
            return firstIndexOfItem(with: uuidData)
        }
        return nil
    }
    
    func contains(uuid: UUID) -> Bool {
        rebuildIndexIfNeeded()
        return uuidindex?[uuid] != nil
    }

    func sort(by areInIncreasingOrder: (ArchivedItem, ArchivedItem) throws -> Bool) rethrows {
        uuidindex = nil
        try all.sort(by: areInIncreasingOrder)
    }
    
    func append<S>(contentsOf newElements: S) where ArchivedItem == S.Element, S: Sequence {
        uuidindex = nil
        all.append(contentsOf: newElements)
    }

    func insert<S>(contentsOf newElements: S, at index: Int) where ArchivedItem == S.Element, S: Collection {
        uuidindex = nil
        all.insert(contentsOf: newElements, at: index)
    }

    @discardableResult
    func remove(at index: Int) -> ArchivedItem {
        uuidindex = nil
        return all.remove(at: index)
    }

    func insert(_ newElement: ArchivedItem, at i: Int) {
        uuidindex = nil
        all.insert(newElement, at: i)
    }
    
    init() {
        all = ContiguousArray<ArchivedItem>()
    }
    
    init(existingItems: ContiguousArray<ArchivedItem>) {
        all = existingItems
    }
    
    func removeAll(keepingCapacity: Bool) {
        uuidindex = nil
        all.removeAll(keepingCapacity: keepingCapacity)
    }
    
    func removeAll(where shouldBeRemoved: (ArchivedItem) throws -> Bool) rethrows {
        uuidindex = nil
        try all.removeAll(where: shouldBeRemoved)
    }
        
    func clearCaches() {
        for drop in all {
            for component in drop.components {
                component.clearCachedFields()
            }
        }
    }
}

final class Model {

	static var brokenMode = false
	static var drops = DropArray()
	static var dataFileLastModified = Date.distantPast

	private static var isStarted = false

	static func reset() {
		drops.removeAll(keepingCapacity: false)
		clearCaches()
		dataFileLastModified = .distantPast
	}
    
    static let loadDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
        return decoder
    }()
    
    static let saveEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
        return e
    }()

	static func reloadDataIfNeeded(maximumItems: Int? = nil) {

		if brokenMode {
			log("Ignoring load, model is broken, app needs restart.")
			return
		}

		var coordinationError: NSError?
		var loadingError: NSError?
		var didLoad = false

		// withoutChanges because we only signal the provider after we have saved
		coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

			if !FileManager.default.fileExists(atPath: url.path) {
                drops.removeAll(keepingCapacity: false)
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
					var newDrops = ContiguousArray<ArchivedItem>()
					newDrops.reserveCapacity(itemCount)
                    
                    d.withUnsafeBytes { pointer in
                        let uuidSequence = pointer.bindMemory(to: uuid_t.self).prefix(itemCount)
                        uuidSequence.forEach { u in
                            let u = UUID(uuid: u)
                            let dataPath = url.appendingPathComponent(u.uuidString)
                            if let data = try? Data(contentsOf: dataPath), let item = try? loadDecoder.decode(ArchivedItem.self, from: data) {
                                newDrops.append(item)
                            }
                        }
                    }
                    
					drops = DropArray(existingItems: newDrops)
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

    static var doneIngesting: Bool {
        return !drops.all.contains { ($0.needsReIngest && !$0.needsDeletion) || $0.loadingProgress != nil }
    }

	static var visibleDrops: ContiguousArray<ArchivedItem> {
		return drops.all.filter { $0.isVisible }
	}

	static let itemsDirectoryUrl: URL = {
		return appStorageUrl.appendingPathComponent("items", isDirectory: true)
	}()

	static let temporaryDirectoryUrl: URL = {
		let url = appStorageUrl.appendingPathComponent("temporary", isDirectory: true)
		let fm = FileManager.default
        let p = url.path
		if fm.fileExists(atPath: p) {
			try? fm.removeItem(atPath: p)
		}
		try! fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		return url
	}()

	static func item(uuid: String) -> ArchivedItem? {
        if let uuidData = UUID(uuidString: uuid) {
            return item(uuid: uuidData)
        } else {
            return nil
        }
	}

	static func item(uuid: UUID) -> ArchivedItem? {
        return drops.firstItem(with: uuid)
	}

	static func item(shareId: String) -> ArchivedItem? {
		return drops.all.first { $0.cloudKitRecord?.share?.recordID.recordName == shareId }
	}

    static func component(uuid: UUID) -> Component? {
        for d in drops.all {
            if let c = d.components.first(where: { $0.uuid == uuid }) {
                return c
            }
        }
        return nil
    }
    
	static func component(uuid: String) -> Component? {
        if let uuidData = UUID(uuidString: uuid) {
            return component(uuid: uuidData)
        } else {
            return nil
        }
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
