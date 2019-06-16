
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
	}

	override func getFileItems(from: NSFileProviderPage?, length: Int?) -> ([FileProviderConvertible], NSFileProviderPage?) {

		FileProviderExtension.ensureCurrent(checkAnyway: true)

		var workingSetItems = [FileProviderConvertible]()

		for drop in Model.visibleDrops {
			if drop.hasTagData || drop.hasFavouriteRankData {
				workingSetItems.append(drop)
			}
			for typeItem in drop.typeItems where typeItem.hasTagData {
				if drop.typeItems.count == 1 { // ensure parent is not listed, as the child is what's visible
					let id = typeItem.parentUuid
					workingSetItems.removeAll { $0.uuid == id }
				}
				workingSetItems.append(typeItem)
			}
		}

		var lastPage: NSFileProviderPage?
		if let length = length {
			let start: Int
			if let from = from, let indexString = String(data: from.rawValue, encoding: .utf8), let index = Int(indexString) {
				start = min(workingSetItems.count, index)
			} else {
				start = 0
			}

			let end = min(workingSetItems.count, start + length)
			workingSetItems = Array(workingSetItems[start ..< end])

			if workingSetItems.count == length, let d = workingSetItems.last?.uuid.uuidString.data(using: .utf8) {
				lastPage = NSFileProviderPage(d)
			}

		}

		return (workingSetItems, lastPage)
	}
}
