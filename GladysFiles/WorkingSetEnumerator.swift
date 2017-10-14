
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
	}

	override var fileItems: [FileProviderItem] {

		var taggedItems = [FileProviderItem]()
		for drop in model.drops {
			if drop.hasTagData {
				taggedItems.append(FileProviderItem(drop))
			}
			if drop.typeItems.count > 1 {
				for typeItem in drop.typeItems {
					if typeItem.hasTagData {
						taggedItems.append(FileProviderItem(typeItem))
					}
				}
			}
		}

		if sortByDate {
			return taggedItems.sorted { $0.contentModificationDate ?? .distantPast < $1.contentModificationDate ?? .distantPast }
		} else {
			return taggedItems.sorted { $0.filename < $1.filename }
		}
	}
}
