
import Foundation

extension ArchivedDropItemType {

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

	var sharedLink: URL? {

		let f = FileManager.default
		guard f.fileExists(atPath: bytesPath.path) else { return nil }

		let sharedPath = folderUrl.appendingPathComponent("shared-blob")
		let linkURL = sharedPath.appendingPathComponent("shared").appendingPathExtension(fileExtension ?? ".bin")
		let originalURL = bytesPath
		if f.fileExists(atPath: linkURL.path) && Model.modificationDate(for: linkURL) == Model.modificationDate(for: originalURL) {
			return linkURL
		}

		log("Updating shared link at \(linkURL.path)")

		if f.fileExists(atPath: sharedPath.path) {
			try! f.removeItem(at: sharedPath)
		}
		try! f.createDirectory(atPath: sharedPath.path, withIntermediateDirectories: true, attributes: nil)
		try! f.linkItem(at: originalURL, to: linkURL)

		return linkURL
	}
}
