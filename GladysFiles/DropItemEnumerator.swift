
import FileProvider

final class DropItemEnumerator: CommonEnumerator {

	init(dropItem: ArchivedDropItem) {
		super.init(uuid: dropItem.uuid.uuidString)
	}

	override var fileItems: [FileProviderItem] {
		let uuidData = UUID(uuidString: uuid)
		guard let dropItem = undeletedDrops.first(where: { $0.uuid == uuidData }) else {
			return []
		}
		if sortByDate {
			return dropItem.typeItems.sorted { $0.updatedAt < $1.updatedAt }.map { FileProviderItem($0) }
		} else {
			return dropItem.typeItems.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
	}
}
