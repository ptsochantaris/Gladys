
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
	}

	override func getFileItems() -> [FileProviderItem] {

		FileProviderExtension.ensureCurrent(checkAnyway: true)

		var workingSetItems = [FileProviderItem]()

		for drop in Model.visibleDrops {
			if drop.hasTagData || drop.hasFavouriteRankData {
				workingSetItems.append(FileProviderItem(drop))
			}
			for typeItem in drop.typeItems where typeItem.hasTagData {
				let fpi = FileProviderItem(typeItem)
				let id = fpi.itemIdentifier.rawValue
				if let index = workingSetItems.firstIndex(where: { $0.itemIdentifier.rawValue == id }) { // a type item is overriding the parent
					workingSetItems.remove(at: index)
				}
				workingSetItems.append(fpi)
			}
		}

		if sortByDate {
			return workingSetItems.sorted { $0.contentModificationDate ?? .distantPast < $1.contentModificationDate ?? .distantPast }
		} else {
			return workingSetItems.sorted { $0.filename < $1.filename }
		}
	}
}
