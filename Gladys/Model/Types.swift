
import UIKit

func log(_ line: @autoclosure ()->String) {
	#if DEBUG
		print(line())
	#endif
}

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

	func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale: Bool = false) -> UIImage {

		let s = useScreenScale ? UIScreen.main.scale : scale
		let mySize = size
		let widthRatio  = targetSize.width  / mySize.width
		let heightRatio = targetSize.height / mySize.height

		let ratio: CGFloat
		if limitTo < 1 {
			ratio = min(widthRatio, heightRatio) * limitTo * s
		} else {
			ratio = max(widthRatio, heightRatio) * limitTo * s
		}

		let scaledWidthPixels = Int(mySize.width * ratio)
		let scaledHeightPixels = Int(mySize.height * ratio)

		let targetPixelWidth = targetSize.width * s
		let targetPixelHeight = targetSize.height * s
		let offsetX = (Int(targetPixelWidth) - scaledWidthPixels) / 2
		let offsetY = (Int(targetPixelHeight) - scaledHeightPixels) / 2

		let orientation = imageOrientation
		var transform = CGAffineTransform.identity
		switch orientation {
		case .down, .downMirrored:
			transform = transform.translatedBy(x: targetPixelWidth, y: targetPixelHeight).rotated(by: .pi)
		case .left, .leftMirrored:
			transform = transform.translatedBy(x: targetPixelWidth, y: 0).rotated(by: .pi/2)
		case .right, .rightMirrored:
			transform = transform.translatedBy(x: 0, y: targetPixelHeight).rotated(by: -.pi/2)
		default: break
		}

		switch orientation {
		case .upMirrored, .downMirrored:
			transform = transform.translatedBy(x: targetPixelWidth, y: 0).scaledBy(x: -1, y: 1)
		case .leftMirrored, .rightMirrored:
			transform = transform.translatedBy(x: targetPixelHeight, y: 0).scaledBy(x: -1, y: 1)
		default: break
		}

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

		switch orientation {
		case .left, .leftMirrored, .right, .rightMirrored:
			c.draw(imageRef, in: CGRect(x: offsetY, y: offsetX, width: scaledHeightPixels, height: scaledWidthPixels))
		default:
			c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: scaledWidthPixels, height: scaledHeightPixels))
		}

		return UIImage(cgImage: c.makeImage()!, scale: s, orientation: .up)
	}
}
