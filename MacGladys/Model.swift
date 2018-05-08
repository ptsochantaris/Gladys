
import Foundation
import CoreSpotlight

final class Model {

	static func reset() {
		drops.removeAll(keepingCapacity: false)
		dataFileLastModified = .distantPast
	}

	static func reloadDataIfNeeded() {

		var didLoad = false
		let url = itemsDirectoryUrl

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
			}
		} else {
			drops = []
			log("Starting fresh store")
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

	static func saveIndexOnly() {

		let itemsToSave = drops.filter { $0.goodToSave }

		saveQueue.async {
			let url = itemsDirectoryUrl
			do {
				log("Storing updated item index")

				var uuidData = Data()
				uuidData.reserveCapacity(itemsToSave.count * 16)
				for item in itemsToSave {
					let u = item.uuid
					let t = u.uuid
					uuidData.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
				}

				let fm = FileManager.default
				if !fm.fileExists(atPath: url.path) {
					try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
				}
				try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

				if let dataModified = modificationDate(for: url) {
					dataFileLastModified = dataModified
				}
			} catch {
				log("Saving index error: \(error.finalDescription)")
			}
		}
	}

	static func coordinatedSave(allItems: [ArchivedDropItem], dirtyUuids: [UUID]) throws {
		let url = itemsDirectoryUrl
		let fm = FileManager.default
		if !fm.fileExists(atPath: url.path) {
			try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}

		let e = dirtyUuids.count > 0 ? JSONEncoder() : nil

		var uuidData = Data()
		uuidData.reserveCapacity(allItems.count * 16)
		for item in allItems {
			let u = item.uuid
			let t = u.uuid
			uuidData.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
			if let e = e, dirtyUuids.contains(u) {
				try autoreleasepool {
					try e.encode(item).write(to: url.appendingPathComponent(u.uuidString), options: .atomic)
				}
			}
		}
		try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

		if let filesInDir = fm.enumerator(atPath: url.path)?.allObjects as? [String] {
			if (filesInDir.count - 1) > allItems.count { // old file exists, let's find it
				let uuidStrings = allItems.map { $0.uuid.uuidString }
				for file in filesInDir {
					if !uuidStrings.contains(file) && file != "uuids" { // old file
						log("Removing file for non-existent item: \(file)")
						try? fm.removeItem(atPath: url.appendingPathComponent(file).path)
					}
				}
			}
		}

		if let dataModified = modificationDate(for: url) {
			dataFileLastModified = dataModified
		}
	}

	static func prepareToSave() {
		rebuildLabels()
	}

	static func startupComplete() {

		// cleanup, in case of previous crashes, cancelled transfers, etc

		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(at: appStorageUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else { return }
		let uuids = items.compactMap { UUID(uuidString: $0.lastPathComponent) }
		let nonExistingUUIDs = uuids.filter { uuid -> Bool in
			return !drops.contains { $0.uuid == uuid }
		}
		for uuid in nonExistingUUIDs {
			let url = appStorageUrl.appendingPathComponent(uuid.uuidString)
			try? fm.removeItem(at: url)
		}

		rebuildLabels()
	}

	static func saveComplete() {
		NotificationCenter.default.post(name: .SaveComplete, object: nil)
		if saveIsDueToSyncFetch {
			saveIsDueToSyncFetch = false
			log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
		} else {
			log("Will sync up after a local save")
			CloudManager.sync { error in
				if let error = error {
					log("Error in push after save: \(error.finalDescription)")
				}
			}
		}
	}
}
