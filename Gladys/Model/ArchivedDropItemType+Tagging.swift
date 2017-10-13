
import Foundation

extension ArchivedDropItemType {

	private var tagDataPath: URL {
		return folderUrl.appendingPathComponent("tags", isDirectory: false)
	}

	var tagData: Data? {
		set {
			let location = tagDataPath
			if newValue == nil {
				let f = FileManager.default
				if f.fileExists(atPath: location.path) {
					try! f.removeItem(at: location)
				}
			} else {
				try! newValue?.write(to: location, options: .atomic)
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
}
