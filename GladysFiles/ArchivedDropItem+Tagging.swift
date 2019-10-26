
import FileProvider
import SafeUnarchiver

extension ArchivedDropItem {
	var tagDataPath: URL {
		return folderUrl.appendingPathComponent("tags", isDirectory: false)
	}

	var hasTagData: Bool {
		return FileManager.default.fileExists(atPath: tagDataPath.path)
	}

	var tagData: Data? {
		set {
			let location = tagDataPath
			if let newValue = newValue {
				try! newValue.write(to: location, options: .atomic)
			} else {
				let f = FileManager.default
				if f.fileExists(atPath: location.path) {
					try! f.removeItem(at: location)
				}
			}
			NSFileProviderManager.default.signalEnumerator(for: .workingSet) { error in
				if let e = error {
					log("Error signalling: \(e.finalDescription)")
				}
			}
		}
		get {
			let location = tagDataPath
			if FileManager.default.fileExists(atPath: location.path) {
				return try! Data(contentsOf: location, options: [.alwaysMapped])
			} else {
				return nil
			}
		}
	}

	private var favoriteRankPath: URL {
		return folderUrl.appendingPathComponent("favouriteRank", isDirectory: false)
	}

	var hasFavouriteRankData: Bool {
		return FileManager.default.fileExists(atPath: favoriteRankPath.path)
	}

	var favoriteRank: NSNumber? {
		set {
			let location = favoriteRankPath
			if let newValue = newValue {
                try? SafeArchiver.archive(newValue)?.write(to: location, options: .atomic)
			} else {
				let f = FileManager.default
				if f.fileExists(atPath: location.path) {
					try! f.removeItem(at: location)
				}
			}
		}
		get {
			let location = favoriteRankPath
			if FileManager.default.fileExists(atPath: location.path), let d = try? Data(contentsOf: location, options: []) {
                return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSNumber.self, from: d)
			} else {
				return nil
			}
		}
	}
}
