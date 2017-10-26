
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
	static let ExternalDataUpdated = Notification.Name("ExternalDataUpdated")
	static let LowMemoryModeOn = Notification.Name("LowMemoryModeOn")
	static let ItemModified = Notification.Name("ItemModified")
	static let LabelsUpdated = Notification.Name("LabelsUpdated")
	static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
	static let DetailViewClosing = Notification.Name("DetailViewClosing")
	static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
	static let CloudManagerUpdatedUUIDSequence = Notification.Name("CloudManagerUpdatedUUIDSequence")
	static let ReachabilityChangedNotification = Notification.Name("ReachabilityChangedNotification")
}

extension UIImage {

	func writeBitmap(to url: URL) {
		DispatchQueue.main.async { // TODO improve
			try? UIImagePNGRepresentation(self)?.write(to: url, options: .atomic)
		}
	}

	static func fromBitmap(at url: URL, scale: CGFloat) -> UIImage? {

		guard
			let provider = CGDataProvider(url: url as CFURL),
			let cgImage = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
			else { return nil }

		let W = Int(cgImage.width)
		let H = Int(cgImage.height)

		let c = CGContext(data: nil,
						  width: W,
						  height: H,
						  bitsPerComponent: 8,
						  bytesPerRow: W * 4,
						  space: CGColorSpaceCreateDeviceRGB(),
						  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!

		c.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: W, height: H)))

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
