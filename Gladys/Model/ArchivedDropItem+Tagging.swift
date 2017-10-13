
import Foundation

extension ArchivedDropItem {
	private var tagDataPath: URL {
		return folderUrl.appendingPathComponent("tags", isDirectory: false)
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

	var favoriteRank: NSNumber? {
		set {
			let location = favoriteRankPath
			if let newValue = newValue {
				try! NSKeyedArchiver.archivedData(withRootObject: newValue).write(to: location, options: .atomic)
			} else {
				let f = FileManager.default
				if f.fileExists(atPath: location.path) {
					try! f.removeItem(at: location)
				}
			}
		}
		get {
			let location = favoriteRankPath
			if FileManager.default.fileExists(atPath: location.path) {
				let d = try! Data(contentsOf: location, options: [.alwaysMapped])
				return NSKeyedUnarchiver.unarchiveObject(with: d) as? NSNumber
			} else {
				return nil
			}
		}
	}
}
