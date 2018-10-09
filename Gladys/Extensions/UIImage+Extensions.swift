//
//  UIImage+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension UIImage {

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
