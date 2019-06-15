
import Foundation
import FileProvider

final class DropItemEnumerator: CommonEnumerator {

	init(dropItem: ArchivedDropItem) {
		super.init(uuid: dropItem.uuid.uuidString)
	}

	override func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderItem], NSFileProviderPage?) {

		FileProviderExtension.ensureCurrent(checkAnyway: true)
		
		guard let dropItem = Model.item(uuid: uuid) else {
			return ([], nil)
		}

		let slice: [ArchivedDropItemType]
		var lastPage: NSFileProviderPage?
		if let length = length {
			if let from = from, let itemUUIDString = String(data: from.rawValue, encoding: .utf8), let itemUUID = UUID(uuidString: itemUUIDString) {
				slice = Array(dropItem.typeItems.drop { $0.uuid != itemUUID }.prefix(length))
			} else {
				slice = Array(dropItem.typeItems.prefix(length))
			}

			if slice.count == length, let d = slice.last?.uuid.uuidString.data(using: .utf8) {
				lastPage = NSFileProviderPage(d)
			}

		} else {
			slice = dropItem.typeItems
		}

		return (slice.map { FileProviderItem($0) }, lastPage)
	}
}
