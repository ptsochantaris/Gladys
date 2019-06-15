
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
	}

	override func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderItem], NSFileProviderPage?) {

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

		var lastPage: NSFileProviderPage?
		if let length = length {
			if let from = from, let itemUUIDString = String(data: from.rawValue, encoding: .utf8) {
				workingSetItems = Array(workingSetItems.drop { $0.itemIdentifier.rawValue != itemUUIDString }.prefix(length))
			} else {
				workingSetItems = Array(workingSetItems.prefix(length))
			}

			if workingSetItems.count == length, let d = workingSetItems.last?.itemIdentifier.rawValue.data(using: .utf8) {
				lastPage = NSFileProviderPage(d)
			}
		}

		return (workingSetItems, lastPage)
	}
}
