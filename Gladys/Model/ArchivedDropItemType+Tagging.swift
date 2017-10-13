
import Foundation

extension ArchivedDropItemType {

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
}
