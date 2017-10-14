
import FileProvider

final class DropItemEnumerator: CommonEnumerator {

	private var dropItem: ArchivedDropItem

	init(dropItem: ArchivedDropItem) {
		self.dropItem = dropItem
		super.init(uuid: dropItem.uuid.uuidString)
	}

	override var fileItems: [FileProviderItem] {
		if sortByDate {
			return dropItem.typeItems.sorted { $0.updatedAt < $1.updatedAt }.map { FileProviderItem($0) }
		} else {
			return dropItem.typeItems.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
	}
}
