
import UIKit

func log(_ line: @autoclosure ()->String) {
	#if DEBUG
		print(line())
	#endif
}

enum ArchivedDropItemDisplayType: Int {
	case fit, fill, center, circle
}

protocol LoadCompletionDelegate: class {
	func loadCompleted(sender: AnyObject, success: Bool)
	func loadingProgress(sender: AnyObject)
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
	static let ExternalDataUpdated = Notification.Name("ExternalDataUpdated")
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

	func writeBitmap(to path: String) {
		let imageRef = cgImage!
		let W = imageRef.width
		let H =	imageRef.height
		let byteCount = W * 4 * H
		let c = CGContext(data: nil,
		                  width: W,
		                  height: H,
		                  bitsPerComponent: 8,
		                  bytesPerRow: W * 4,
		                  space: CGColorSpaceCreateDeviceRGB(),
		                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!
		c.draw(imageRef, in: CGRect(origin: .zero, size: CGSize(width: W, height: H)))

		let F = open(path.cString(using: .utf8)!, O_WRONLY | O_CREAT, S_IRUSR | S_IWUSR)
		write(F, c.data!, byteCount)
		close(F)
	}

	static func fromBitmap(at path: String, width: CGFloat, height: CGFloat, scale: CGFloat) -> UIImage {

		let W = Int(width * scale)
		let H = Int(height * scale)

		let c = CGContext(data: nil,
						  width: W,
						  height: H,
						  bitsPerComponent: 8,
						  bytesPerRow: W * 4,
						  space: CGColorSpaceCreateDeviceRGB(),
						  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!

		let byteCount = Int(W * H * 4)

		let F = open(path.cString(using: .utf8)!, O_RDONLY)
		read(F, c.data!, byteCount)
		close(F)

		return UIImage(cgImage: c.makeImage()!, scale: scale, orientation: .up)
	}

	func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale: Bool = false) -> UIImage {

		let mySizePixelWidth = size.width * scale
		let mySizePixelHeight = size.height * scale

		let s = useScreenScale ? UIScreen.main.scale : scale
		let outputImagePixelWidth = targetSize.width * s
		let outputImagePixelHeight = targetSize.height * s

		let widthRatio  = outputImagePixelWidth  / mySizePixelWidth
		let heightRatio = outputImagePixelHeight / mySizePixelHeight

		let ratio: CGFloat
		if limitTo < 1 {
			ratio = min(widthRatio, heightRatio) * limitTo
		} else {
			ratio = max(widthRatio, heightRatio) * limitTo
		}

		let drawnImageWidthPixels = Int(mySizePixelWidth * ratio)
		let drawnImageHeightPixels = Int(mySizePixelHeight * ratio)

		let offsetX = (Int(outputImagePixelWidth) - drawnImageWidthPixels) / 2
		let offsetY = (Int(outputImagePixelHeight) - drawnImageHeightPixels) / 2

		let orientation = imageOrientation
		var transform: CGAffineTransform
		switch orientation {
		case .down, .downMirrored:
			transform = CGAffineTransform(translationX: outputImagePixelWidth, y: outputImagePixelHeight).rotated(by: .pi)
		case .left, .leftMirrored:
			transform = CGAffineTransform(translationX: outputImagePixelWidth, y: 0).rotated(by: .pi/2)
		case .right, .rightMirrored:
			transform = CGAffineTransform(translationX: 0, y: outputImagePixelHeight).rotated(by: -.pi/2)
		default:
			transform = .identity
		}

		switch orientation {
		case .upMirrored, .downMirrored:
			transform = transform.translatedBy(x: outputImagePixelWidth, y: 0).scaledBy(x: -1, y: 1)
		case .leftMirrored, .rightMirrored:
			transform = transform.translatedBy(x: outputImagePixelHeight, y: 0).scaledBy(x: -1, y: 1)
		default: break
		}

		let imageRef = cgImage!
		let c = CGContext(data: nil,
		                  width: Int(outputImagePixelWidth),
		                  height: Int(outputImagePixelHeight),
		                  bitsPerComponent: 8,
		                  bytesPerRow: Int(outputImagePixelWidth) * 4,
		                  space: CGColorSpaceCreateDeviceRGB(),
		                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!
		c.interpolationQuality = .high
		c.concatenate(transform)

		switch orientation {
		case .left, .leftMirrored, .right, .rightMirrored:
			c.draw(imageRef, in: CGRect(x: offsetY, y: offsetX, width: drawnImageHeightPixels, height: drawnImageWidthPixels))
		default:
			c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: drawnImageWidthPixels, height: drawnImageHeightPixels))
		}

		return UIImage(cgImage: c.makeImage()!, scale: s, orientation: .up)
	}
}
