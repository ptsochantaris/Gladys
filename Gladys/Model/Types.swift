
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

	func limited(to targetSize: CGSize, shouldHalve: Bool) -> UIImage {

		let targetPixelWidth = targetSize.width * scale
		let targetPixelHeight = targetSize.height * scale

		var transform = CGAffineTransform.identity
		switch imageOrientation {
		case .down, .downMirrored:
			transform = transform.translatedBy(x: targetPixelWidth, y: targetPixelHeight).rotated(by: .pi)
		case .left, .leftMirrored:
			transform = transform.translatedBy(x: targetPixelWidth, y: 0).rotated(by: .pi/2)
		case .right, .rightMirrored:
			transform = transform.translatedBy(x: 0, y: targetPixelHeight).rotated(by: -.pi/2)
		default: break
		}

		switch imageOrientation {
		case .upMirrored, .downMirrored:
			transform = transform.translatedBy(x: targetPixelWidth, y: 0).scaledBy(x: -1, y: 1)
		case .leftMirrored, .rightMirrored:
			transform = transform.translatedBy(x: targetPixelHeight, y: 0).scaledBy(x: -1, y: 1)
		default: break
		}

		let s = scale
		let imageRef = cgImage!
		let c = CGContext(data: nil,
		                  width: Int(targetPixelWidth),
		                  height: Int(targetPixelHeight),
		                  bitsPerComponent: 8,
		                  bytesPerRow: Int(targetPixelHeight) * 4,
		                  space: CGColorSpaceCreateDeviceRGB(),
		                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		c.interpolationQuality = .high
		c.concatenate(transform)

		let widthRatio  = targetSize.width  / size.width
		let heightRatio = targetSize.height / size.height
		let ratio = max(widthRatio, heightRatio) * (shouldHalve ? 0.5 : 1)

		let scaledWidth = size.width * ratio
		let scaledHeight = size.height * ratio

		let scaledWidthPixels = Int(scaledWidth * s)
		let scaledHeightPixels = Int(scaledHeight * s)

		let offsetX = (Int(targetPixelWidth) - scaledWidthPixels) / 2
		let offsetY = (Int(targetPixelHeight) - scaledHeightPixels) / 2

		switch imageOrientation {
		case .left, .leftMirrored, .right, .rightMirrored:
			c.draw(imageRef, in: CGRect(x: offsetY, y: offsetX, width: scaledHeightPixels, height: scaledWidthPixels))
		default:
			c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: scaledWidthPixels, height: scaledHeightPixels))
		}
		return UIImage(cgImage: c.makeImage()!, scale: scale, orientation: .up)
	}
}
