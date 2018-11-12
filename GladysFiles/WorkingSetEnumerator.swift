
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
	}

	override func getFileItems() -> [FileProviderItem] {

		FileProviderExtension.ensureCurrent()
		let taggedItems = Model.visibleDrops.compactMap { drop -> FileProviderItem? in
			if drop.hasTagData {
				return FileProviderItem(drop)
			}
			if drop.typeItems.count > 1 {
				for typeItem in drop.typeItems {
					if typeItem.hasTagData {
						return FileProviderItem(typeItem)
					}
				}
			}
			return nil
		}

		if sortByDate {
			return taggedItems.sorted { $0.contentModificationDate ?? .distantPast < $1.contentModificationDate ?? .distantPast }
		} else {
			return taggedItems.sorted { $0.filename < $1.filename }
		}
	}
}
