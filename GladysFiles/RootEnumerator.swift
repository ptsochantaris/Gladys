
import FileProvider

final class RootEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.rootContainer.rawValue)
	}

	override var fileItems: [FileProviderItem] {
		if sortByDate {
			return model.drops.sorted { $0.createdAt < $1.createdAt }.map { FileProviderItem($0) }
		} else {
			return model.drops.sorted { $0.oneTitle < $1.oneTitle }.map { FileProviderItem($0) }
		}
	}
}
