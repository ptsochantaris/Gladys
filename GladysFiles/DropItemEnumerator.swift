
import FileProvider

final class DropItemEnumerator: CommonEnumerator {

	init(dropItem: ArchivedDropItem) {
		super.init(uuid: dropItem.uuid.uuidString)
	}

	override func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderConvertible], NSFileProviderPage?) {

		FileProviderExtension.ensureCurrent(checkAnyway: true)
		
		guard let dropItem = Model.item(uuid: uuid) else {
			return ([], nil)
		}

		let slice: [FileProviderConvertible]
		var lastPage: NSFileProviderPage?
		if let length = length {
			let drops = dropItem.typeItems
			let start: Int
			if let from = from, let indexString = String(data: from.rawValue, encoding: .utf8), let index = Int(indexString) {
				start = min(drops.count, index)
			} else {
				start = 0
			}

			let end = min(drops.count, start + length)
			slice = Array(drops[start ..< end])

			if slice.count == length, let d = slice.last?.uuid.uuidString.data(using: .utf8) {
				lastPage = NSFileProviderPage(d)
			}

		} else {
			slice = dropItem.typeItems
		}

		return (slice, lastPage)
	}
}
