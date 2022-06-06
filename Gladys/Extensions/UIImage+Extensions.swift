//
//  UIImage+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

let screenScale = UIScreen.main.scale
let pixelSize: CGFloat = 1 / screenScale

extension UIImage {
    private static let fromFileOptions: CFDictionary = [
        kCGImageSourceShouldCache: kCFBooleanFalse
    ] as CFDictionary

    private static let regularFormat: UIGraphicsImageRendererFormat = {
        let f = UIGraphicsImageRendererFormat()
        f.preferredRange = .standard
        f.scale = 1
        return f
    }()

    private static let templateFormat: UIGraphicsImageRendererFormat = {
        let f = UIGraphicsImageRendererFormat()
        f.preferredRange = .standard
        f.scale = screenScale
        return f
    }()

    static func fromFile(_ url: URL, template: Bool) -> UIImage? {
        if #available(iOS 15.0, *) {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: template ? screenScale : 1) {
                if template {
                    return image.withRenderingMode(.alwaysTemplate).preparingForDisplay()
                } else {
                    return image.preparingForDisplay()
                }
            }
            return nil
        }

        guard let provider = CGDataProvider(url: url as CFURL),
              let source = CGImageSourceCreateWithDataProvider(provider, nil),
              let imageRef = CGImageSourceCreateImageAtIndex(source, 0, fromFileOptions) else {
            return nil
        }

        let format = template ? templateFormat : regularFormat
        let scale = format.scale
        let w = CGFloat(imageRef.width) / scale
        let h = CGFloat(imageRef.height) / scale
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let outputImage = UIGraphicsImageRenderer(bounds: rect, format: format).image { rc in
            let c = rc.cgContext
            c.translateBy(x: 0, y: h)
            c.scaleBy(x: 1, y: -1)
            c.draw(imageRef, in: rect)
        }

        if template {
            return outputImage.withRenderingMode(.alwaysTemplate)
        } else {
            return outputImage
        }
    }

    final func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale: Bool = false, singleScale: Bool = false) -> UIImage {
        let targetScale = singleScale ? 1 : scale
        let mySizePixelWidth = size.width * targetScale
        let mySizePixelHeight = size.height * targetScale

        let s = useScreenScale ? screenScale : targetScale
        let outputImagePixelWidth = targetSize.width * s
        let outputImagePixelHeight = targetSize.height * s

        let widthRatio = outputImagePixelWidth / mySizePixelWidth
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
            transform = CGAffineTransform(translationX: outputImagePixelWidth, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = CGAffineTransform(translationX: 0, y: outputImagePixelHeight).rotated(by: -.pi / 2)
        default:
            transform = .identity
        }

        switch orientation {
        case .downMirrored, .upMirrored:
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

    private static let sharedCiContext = CIContext()

    final func desaturated(darkMode: Bool) async -> UIImage {
        guard let ciImage = CIImage(image: self) else {
            return self
        }
        let p1 = darkMode ? "inputColor0" : "inputColor1"
        let p2 = darkMode ? "inputColor1" : "inputColor0"
        let a: CGFloat = darkMode ? 0.05 : 0.2
        let blackAndWhiteImage = ciImage
            .applyingFilter("CIFalseColor", parameters: [
                p1: CIColor(color: .systemBackground),
                p2: CIColor(color: .secondaryLabel.withAlphaComponent(a))
            ])
        return await Task.detached {
            if let cgImage = UIImage.sharedCiContext.createCGImage(blackAndWhiteImage, from: blackAndWhiteImage.extent) {
                let img = UIImage(cgImage: cgImage)
                return img
            } else {
                return self
            }
        }.value
    }
}
