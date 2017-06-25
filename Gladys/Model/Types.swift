
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

extension FileManager {
	func contentSizeOfDirectory(at directoryURL: URL) -> Int64 {
		var contentSize: Int64 = 0
		if let e = enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
			for itemURL in e {
				if let itemURL = itemURL as? URL {
					let s = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
					contentSize += Int64(s ?? 0)
				}
			}
		}
		return contentSize
	}
}

extension Notification.Name {
	static let SaveComplete = Notification.Name("SaveComplete")
	static let SearchResultsUpdated = Notification.Name("SearchResultsUpdated")
	static let DeleteSelected = Notification.Name("DeleteSelected")
}

let diskSizeFormatter = ByteCountFormatter()

let dateFormatter: DateFormatter = {
	let d = DateFormatter()
	d.doesRelativeDateFormatting = true
	d.dateStyle = .medium
	d.timeStyle = .medium
	return d
}()

extension UIImage {
	func limited(to targetSize: CGSize) -> UIImage {
		let mySize = size

		let widthRatio  = targetSize.width  / mySize.width
		let heightRatio = targetSize.height / mySize.height

		let ratio = min(20, max(widthRatio, heightRatio))
		let newSize = CGSize(width: mySize.width * ratio, height: mySize.height * ratio)

		let offset = CGPoint(x: (targetSize.width - newSize.width) * 0.5,
		                     y: (targetSize.height - newSize.height) * 0.5)

		UIGraphicsBeginImageContextWithOptions(targetSize, false, 1)
		draw(in: CGRect(origin: offset, size: newSize))
		let newImage = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()

		return newImage
	}
}
