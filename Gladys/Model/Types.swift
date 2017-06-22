
import UIKit

struct ArchivedDropDisplayInfo {
	let image: UIImage?
	let imageContentMode: ArchivedDropItemDisplayType
	let title: String?
	let accessoryText: String?
	let titleAlignment: NSTextAlignment

	init(image: UIImage?, imageContentMode: ArchivedDropItemDisplayType, title: String?, accessoryText: String?, titleAlignment: NSTextAlignment) {
		self.image = image
		self.imageContentMode = imageContentMode
		self.title = title
		self.accessoryText = (accessoryText != title) ? accessoryText : nil
		self.titleAlignment = titleAlignment
	}
}

enum ArchivedDropItemDisplayType: Int {
	case fit, fill, center, circle
}

protocol LoadCompletionDelegate: class {
	func loadCompleted(sender: AnyObject, success: Bool)
}

