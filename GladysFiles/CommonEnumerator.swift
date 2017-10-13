
import FileProvider

class CommonEnumerator: NSObject {
	let uuid: String

	var sortByDate = false
	var currentAnchor = NSFileProviderSyncAnchor("0".data(using: .utf8)!)

	init(uuid: String) {
		self.uuid = uuid
		super.init()
	}

	@objc func invalidate() {
	}

	@objc func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
		completionHandler(currentAnchor)
	}

	func incrementAnchor() {
		let newAnchorCount = Int64(String(data: currentAnchor.rawValue, encoding: .utf8)!)! + 1
		currentAnchor = NSFileProviderSyncAnchor(String(newAnchorCount).data(using: .utf8)!)
	}

	deinit {
		log("Enumerator for \(uuid) shut down")
	}
}
