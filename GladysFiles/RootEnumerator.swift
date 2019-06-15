
import FileProvider

final class RootEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.rootContainer.rawValue)
	}

	override func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderItem], NSFileProviderPage?) {

		FileProviderExtension.ensureCurrent(checkAnyway: true)

		let slice: [ArchivedDropItem]
		var lastPage: NSFileProviderPage?
		if let length = length {
			if let from = from, let itemUUIDString = String(data: from.rawValue, encoding: .utf8), let itemUUID = UUID(uuidString: itemUUIDString) {
				slice = Array(Model.visibleDrops.drop { $0.uuid != itemUUID }.prefix(length))
			} else {
				slice = Array(Model.visibleDrops.prefix(length))
			}

			if slice.count == length, let d = slice.last?.uuid.uuidString.data(using: .utf8) {
				lastPage = NSFileProviderPage(d)
			}
		} else {
			slice = Model.visibleDrops
		}

		return (slice.map { FileProviderItem($0) }, lastPage)
	}
}
