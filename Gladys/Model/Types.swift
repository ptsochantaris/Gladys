
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
	func loadCompleted(sender: AnyObject)
}

extension Data {
	var isPlist: Bool {
		guard count > 6 else { return false }
		return withUnsafeBytes { (x: UnsafePointer<UInt8>) -> Bool in
			return x[0] == 0x62
				&& x[1] == 0x70
				&& x[2] == 0x6c
				&& x[3] == 0x69
				&& x[4] == 0x73
				&& x[5] == 0x74
		}
	}
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
	static let ItemCollectionNeedsDisplay = Notification.Name("ItemCollectionNeedsDisplay")
	static let ExternalDataUpdated = Notification.Name("ExternalDataUpdated")
	static let LowMemoryModeOn = Notification.Name("LowMemoryModeOn")
	static let ItemModified = Notification.Name("ItemModified")
	static let LabelsUpdated = Notification.Name("LabelsUpdated")
	static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
	static let DetailViewClosing = Notification.Name("DetailViewClosing")
	static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
	static let ReachabilityChanged = Notification.Name("ReachabilityChanged")
}

extension Error {
	var finalDescription: String {
		let err = self as NSError
		return (err.userInfo[NSUnderlyingErrorKey] as? NSError)?.finalDescription ?? err.localizedDescription
	}
}

extension UIImage {

	func writeBitmap(to url: URL) {
		try? UIImagePNGRepresentation(self)?.write(to: url, options: .atomic)
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

	func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale: Bool = false, singleScale: Bool = false) -> UIImage {

		let targetScale = singleScale ? 1 : scale
		let mySizePixelWidth = size.width * targetScale
		let mySizePixelHeight = size.height * targetScale

		let s = useScreenScale ? UIScreen.main.scale : targetScale
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

extension UIView {
	func cover(with view: UIView, insets: UIEdgeInsets = .zero) {
		view.translatesAutoresizingMaskIntoConstraints = false
		addSubview(view)

		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
			view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
			view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
			view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
		])
	}

	func coverUnder(with view: UIView, insets: UIEdgeInsets = .zero) {
		view.translatesAutoresizingMaskIntoConstraints = false
		superview?.insertSubview(view, belowSubview: self)

		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
			view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
			view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
			view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
		])
	}

	func center(on parentView: UIView, offset: CGFloat = 0) {
		translatesAutoresizingMaskIntoConstraints = false
		parentView.addSubview(self)
		NSLayoutConstraint.activate([
			centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
			centerYAnchor.constraint(equalTo: parentView.centerYAnchor, constant: offset)
		])
	}

	static func animate(animations: @escaping ()->Void, completion: ((Bool)->Void)? = nil) {
		UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: animations, completion: completion)
	}
}
