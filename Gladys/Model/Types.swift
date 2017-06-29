
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

	func limited(to tSize: CGSize, shouldHalve: Bool) -> UIImage {

		let transform: CGAffineTransform
		let targetSize: CGSize
		let mySize: CGSize

		let sourcePixelWidth = CGFloat(cgImage!.width)
		let sourcePixelHeight = CGFloat(cgImage!.height)

		switch imageOrientation {
		case .up:
			transform = .identity
			targetSize = tSize
			mySize = size

		case .upMirrored:
			transform = CGAffineTransform(translationX: sourcePixelWidth, y: 0).scaledBy(x: -1, y: 1)
			targetSize = tSize
			mySize = size

		case .down:
			transform = CGAffineTransform(translationX: sourcePixelWidth, y: sourcePixelHeight).rotated(by: .pi)
			targetSize = tSize
			mySize = size

		case .downMirrored:
			transform = CGAffineTransform(translationX: 0, y: sourcePixelHeight).scaledBy(x: 1, y: -1)
			targetSize = tSize
			mySize = size

		case .left:
			transform = CGAffineTransform(translationX: 0, y: sourcePixelWidth).rotated(by: 3 * .pi / 2)
			targetSize = CGSize(width: tSize.height, height: tSize.width)
			mySize = CGSize(width: size.height, height: size.width)

		case .leftMirrored:
			transform = CGAffineTransform(translationX: size.height, y: sourcePixelWidth).scaledBy(x: -1, y: 1).rotated(by: 3 * .pi / 2)
			targetSize = CGSize(width: tSize.height, height: tSize.width)
			mySize = CGSize(width: size.height, height: size.width)

		case .right:
			transform = CGAffineTransform(translationX: sourcePixelHeight, y: 0).rotated(by: .pi / 2)
			targetSize = CGSize(width: tSize.height, height: tSize.width)
			mySize = CGSize(width: size.height, height: size.width)

		case .rightMirrored:
			transform = CGAffineTransform(scaleX: -1, y: 1).rotated(by: .pi / 2)
			targetSize = CGSize(width: tSize.height, height: tSize.width)
			mySize = CGSize(width: size.height, height: size.width)
		}

		let widthRatio  = targetSize.width  / mySize.width
		let heightRatio = targetSize.height / mySize.height
		let ratio = max(widthRatio, heightRatio) * (shouldHalve ? 0.5 : 1)

		let scaledWidth = mySize.width * ratio
		let scaledHeight = mySize.height * ratio

		let s = scale
		let imageRef = cgImage!
		let targetWidthPixels = Int(targetSize.width * s)
		let targetHeightPixels = Int(targetSize.height * s)
		let c = CGContext(data: nil,
		                  width: targetWidthPixels,
		                  height: targetHeightPixels,
		                  bitsPerComponent: 8,
		                  bytesPerRow: targetWidthPixels * 4,
		                  space: CGColorSpaceCreateDeviceRGB(),
		                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		c.interpolationQuality = .high

		if imageOrientation == .left || imageOrientation == .right {
			c.scaleBy(x: -1, y: -1)
			c.translateBy(x: -sourcePixelHeight, y: -CGFloat(targetHeightPixels))
		} else {
			//c.scaleBy(x: 1, y: -1)
			//c.translateBy(x: 0, y: -sourcePixelHeight)
		}

		c.concatenate(transform)

		let scaledWidthPixels = Int(scaledWidth * s)
		let scaledHeightPixels = Int(scaledHeight * s)

		let offsetX = (targetWidthPixels - scaledWidthPixels) / 2
		let offsetY = (targetHeightPixels - scaledHeightPixels) / 2

		c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: scaledWidthPixels, height: scaledHeightPixels))
		return UIImage(cgImage: c.makeImage()!, scale: scale, orientation: .up)
	}
}
