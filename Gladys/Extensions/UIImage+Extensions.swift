//
//  UIImage+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

private let fromFileOptions: CFDictionary = [
    kCGImageSourceShouldCache: kCFBooleanFalse,
    kCGImageSourceShouldAllowFloat: kCFBooleanTrue
] as CFDictionary

let screenScale = UIScreen.main.scale

extension UIImage {

    static func fromFile(_ url: URL, template: Bool) -> UIImage? {
        
        guard let provider = CGDataProvider(url: url as CFURL),
            let source = CGImageSourceCreateWithDataProvider(provider, nil),
            let imageRef = CGImageSourceCreateImageAtIndex(source, 0, fromFileOptions) else {
                return nil
        }
        
        let width = imageRef.width
        let height = imageRef.height
        let alpha: UInt32
        switch imageRef.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            alpha = CGImageAlphaInfo.noneSkipFirst.rawValue
        default:
            alpha = CGImageAlphaInfo.premultipliedFirst.rawValue
        }
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = alpha | CGBitmapInfo.byteOrder32Little.rawValue
        guard let imageContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colourSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        imageContext.draw(imageRef, in: rect)
        if let outputImage = imageContext.makeImage() {
            if template {
                return UIImage(cgImage: outputImage, scale: screenScale, orientation: .up).withRenderingMode(.alwaysTemplate)
            } else {
                return UIImage(cgImage: outputImage, scale: 1, orientation: .up)
            }
        }
        return nil
    }
    
	final func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale: Bool = false, singleScale: Bool = false) -> UIImage {

		let targetScale = singleScale ? 1 : scale
		let mySizePixelWidth = size.width * targetScale
		let mySizePixelHeight = size.height * targetScale

		let s = useScreenScale ? screenScale : targetScale
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
    
    final func desaturated(darkMode: Bool, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let ciImage = CIImage(image: self) else {
                completion(nil)
                return
            }
            let p1 = darkMode ? "inputColor0" : "inputColor1"
            let p2 = darkMode ? "inputColor1" : "inputColor0"
            let a: CGFloat = darkMode ? 0.05 : 0.2
            let blackAndWhiteImage = ciImage
                .applyingFilter("CIFalseColor", parameters: [
                    p1: CIColor(color: UIColor(named: "colorFill")!),
                    p2: CIColor(color: UIColor.secondaryLabel.withAlphaComponent(a))
                ])
            let img = UIImage(ciImage: blackAndWhiteImage)
            DispatchQueue.main.async {
                completion(img)
            }
        }
    }
}
