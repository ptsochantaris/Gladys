
import Foundation

final class DropItemEnumerator: CommonEnumerator {

	init(dropItem: ArchivedDropItem) {
		super.init(uuid: dropItem.uuid.uuidString)
	}

	override func getFileItems() -> [FileProviderItem] {

		FileProviderExtension.ensureCurrent(checkAnyway: true)
		
		guard let dropItem = Model.item(uuid: uuid) else {
			return []
		}
		if sortByDate {
			return dropItem.typeItems.sorted { $0.updatedAt < $1.updatedAt }.map { FileProviderItem($0) }
		} else {
			return dropItem.typeItems.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
	}
}
