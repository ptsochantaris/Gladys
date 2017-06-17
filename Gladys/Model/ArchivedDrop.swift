
import UIKit

final class ArchivedDrop: LoadCompletionCounter {

	private let uuid = UUID()
	private let createdAt = Date()
	private var items: [ArchivedDropItem]!

	var displayInfo: ArchivedDropDisplayInfo {

		let info = ArchivedDropDisplayInfo()

		for i in items {
			if info.image == nil {
				let (img, contentMode) = i.displayIcon
				info.image = img
				info.imageContentMode = contentMode
			}
			if info.title == nil, let title = i.displayTitle {
				info.title = title
			}
		}

		if info.title == nil {
			info.title = "\(createdAt.timeIntervalSinceReferenceDate)" // TODO
		}

		if info.image == nil {
			info.image = #imageLiteral(resourceName: "iconStickyNote")
			info.imageContentMode = .center
		}

		return info
	}

	var dragItems: [UIDragItem] {
		return items.map {
			let i = UIDragItem(itemProvider: $0.itemProvider)
			i.localObject = self
			return i
		}
	}

	init(session: UIDropSession) {

		let progressType = session.progressIndicatorStyle
		NSLog("Should display progress: \(progressType)")

		super.init(loadCount: session.items.count, delegate: nil)
		items = session.items.map {
			if let item = ($0.localObject as? ArchivedDropItem) {
				item.delegate = self
				return item
			} else {
				return ArchivedDropItem(provider: $0.itemProvider, delegate: self)
			}
		}
	}
}

