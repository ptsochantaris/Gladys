
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
	}

	override var fileItems: [FileProviderItem] {
		if sortByDate {
			return model.drops.sorted { $0.createdAt < $1.createdAt }.filter { $0.tagData != nil }.map { FileProviderItem($0) }
		} else {
			return model.drops.sorted { $0.oneTitle < $1.oneTitle }.filter { $0.tagData != nil }.map { FileProviderItem($0) }
		}
	}
}
