
import FileProvider

final class RootEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.rootContainer.rawValue)
	}

	override func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderConvertible], NSFileProviderPage?) {

		FileProviderExtension.ensureCurrent(checkAnyway: true)

		let slice: [FileProviderConvertible]
		var lastPage: NSFileProviderPage?
		if let length = length {
			let drops = Model.visibleDrops
			let start: Int
			if let from = from, let indexString = String(data: from.rawValue, encoding: .utf8), let index = Int(indexString) {
				start = min(drops.count, index)
			} else {
				start = 0
			}

			let end = min(drops.count, start + length)
			slice = Array(drops[start ..< end])

			if slice.count == length, let d = String(end).data(using: .utf8) {
				lastPage = NSFileProviderPage(d)
			}
		} else {
			slice = Model.visibleDrops
		}

		return (slice, lastPage)
	}
}
