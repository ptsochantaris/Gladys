#if canImport(AppKit)
    import AppKit
    @preconcurrency import CoreImage
#elseif os(iOS) || os(visionOS)
    @preconcurrency import CoreImage
    import UIKit
#elseif os(watchOS)
    import WatchKit
#endif
import Foundation
import SwiftUI

public extension CGSize {
    var isCompact: Bool {
        width < 170
    }
}

public extension COLOR {
    func interpolate(with color: COLOR) -> COLOR {
        let (r1, g1, b1, a1) = components
        let (r2, g2, b2, a2) = color.components

        return COLOR(red: r1.interpolated(towards: r2, amount: 0.5),
                     green: g1.interpolated(towards: g2, amount: 0.5),
                     blue: b1.interpolated(towards: b2, amount: 0.5),
                     alpha: a1.interpolated(towards: a2, amount: 0.5))
    }

    var isBright: Bool {
        var bright: CGFloat = 0
        var sat: CGFloat = 0
        #if canImport(AppKit)
            if let convertedColor = usingColorSpace(.deviceRGB) {
                convertedColor.getHue(nil, saturation: &sat, brightness: &bright, alpha: nil)
            }
        #else
            getHue(nil, saturation: &sat, brightness: &bright, alpha: nil)
        #endif
        if sat > 0.7 {
            return bright > 0.9
        } else {
            return bright > 0.7
        }
    }
}

public extension IMAGE {
    static func from(data: Data) async -> IMAGE? {
        await Task.detached {
            IMAGE(data: data)
        }.value
    }

    var swiftUiImage: Image {
        #if canImport(AppKit)
            Image(nsImage: self)
        #else
            Image(uiImage: self)
        #endif
    }

    #if canImport(CoreImage)

        var createCiImage: CIImage? {
            #if canImport(AppKit)
                let cgi = cgImage(forProposedRect: nil, context: nil, hints: nil)
            #else
                let cgi = cgImage
            #endif
            guard let cgi else { return nil }

            return CIImage(cgImage: cgi, options: [.nearestSampling: true])
        }
    #endif
}

#if canImport(CoreImage)

    public extension CIImage {
        private static let sharedCiContext = CIContext(options: [.cacheIntermediates: false])

        var asImage: IMAGE? {
            guard let new = CIImage.sharedCiContext.createCGImage(self, from: extent) else {
                return nil
            }
            #if canImport(AppKit)
                return IMAGE(cgImage: new, size: CGSize(width: 512, height: 512))
            #else
                return IMAGE(cgImage: new)
            #endif
        }

        // with thanks to https://www.hackingwithswift.com/example-code/media/how-to-read-the-average-color-of-a-uiimage-using-ciareaaverage
        private final func calculateAverageColor(rect: CGRect) -> (UInt8, UInt8, UInt8, UInt8)? {
            guard !extent.isEmpty,
                  let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: self, kCIInputExtentKey: CIVector(cgRect: rect)]),
                  let outputImage = filter.outputImage
            else {
                return nil
            }

            var bitmap = [UInt8](repeating: 0, count: 4)
            CIImage.sharedCiContext.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return (bitmap[0], bitmap[1], bitmap[2], bitmap[3])
        }

        final func calculateOuterColor(size: CGSize, top: Bool?) -> COLOR? {
            var cols: (UInt8, UInt8, UInt8, UInt8)?
            let edgeInset: CGFloat = 50
            let H: CGFloat = 20
            let total = edgeInset + H

            if let top, size.width > total, size.height > total {
                let W = size.width - edgeInset * 2
                let sampleSize = CGSize(width: W, height: H)
                if top {
                    cols = calculateAverageColor(rect: CGRect(origin: CGPoint(x: edgeInset, y: size.height - edgeInset), size: sampleSize))
                } else {
                    cols = calculateAverageColor(rect: CGRect(origin: CGPoint(x: edgeInset, y: edgeInset - H), size: sampleSize))
                }
            } else {
                cols = calculateAverageColor(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }

            if let cols {
                if cols.3 < 200 {
                    return nil
                }
                return COLOR(red: CGFloat(cols.0) / 255,
                             green: CGFloat(cols.1) / 255,
                             blue: CGFloat(cols.2) / 255,
                             alpha: CGFloat(cols.3) / 255)
            } else {
                return nil
            }
        }

        private func topGradientFilterImage(distance: CGFloat) -> CIImage? {
            let greenClear = CIColor(red: 0, green: 1, blue: 0, alpha: 0)
            let greenOpaque = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
            let height = extent.height
            let unitDistanceClear = distance * height
            let unitDistanceOpaque = (distance - 0.2) * height

            let gradient = CIFilter(name: "CILinearGradient")!
            gradient.setValue(CIVector(x: 0, y: height - unitDistanceClear), forKey: "inputPoint0")
            gradient.setValue(greenClear, forKey: "inputColor0")
            gradient.setValue(CIVector(x: 0, y: height - unitDistanceOpaque), forKey: "inputPoint1")
            gradient.setValue(greenOpaque, forKey: "inputColor1")
            return gradient.outputImage
        }

        private func bottomGradientFilterImage(distance: CGFloat) -> CIImage? {
            let greenClear = CIColor(red: 0, green: 1, blue: 0, alpha: 0)
            let greenOpaque = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
            let height = extent.height
            let unitDistanceClear = distance * height
            let unitDistanceOpaque = (distance - 0.2) * height

            let gradient = CIFilter(name: "CILinearGradient")!
            gradient.setValue(CIVector(x: 0, y: unitDistanceOpaque), forKey: "inputPoint0")
            gradient.setValue(greenOpaque, forKey: "inputColor0")
            gradient.setValue(CIVector(x: 0, y: unitDistanceClear), forKey: "inputPoint1")
            gradient.setValue(greenClear, forKey: "inputColor1")
            return gradient.outputImage
        }

        private func topMaskOnlyFilter(distance: CGFloat) -> CIImage? {
            let maskedVariableBlur = CIFilter(name: "CIMaskedVariableBlur")!
            maskedVariableBlur.setValue(self, forKey: kCIInputImageKey)
            maskedVariableBlur.setValue(8, forKey: kCIInputRadiusKey)
            maskedVariableBlur.setValue(topGradientFilterImage(distance: distance), forKey: "inputMask")
            return maskedVariableBlur.outputImage
        }

        private func bottomMaskOnlyFilter(distance: CGFloat) -> CIImage? {
            let maskedVariableBlur = CIFilter(name: "CIMaskedVariableBlur")!
            maskedVariableBlur.setValue(self, forKey: kCIInputImageKey)
            maskedVariableBlur.setValue(8, forKey: kCIInputRadiusKey)
            maskedVariableBlur.setValue(bottomGradientFilterImage(distance: distance), forKey: "inputMask")
            return maskedVariableBlur.outputImage
        }

        private func topBottomFilter(top: CGFloat, bottom: CGFloat) -> CIImage? {
            let gradientMask = CIFilter(name: "CIAdditionCompositing")!
            gradientMask.setValue(topGradientFilterImage(distance: top), forKey: kCIInputImageKey)
            gradientMask.setValue(bottomGradientFilterImage(distance: bottom), forKey: kCIInputBackgroundImageKey)

            let maskedVariableBlur = CIFilter(name: "CIMaskedVariableBlur")!
            maskedVariableBlur.setValue(self, forKey: kCIInputImageKey)
            maskedVariableBlur.setValue(8, forKey: kCIInputRadiusKey)
            maskedVariableBlur.setValue(gradientMask.outputImage, forKey: "inputMask")
            return maskedVariableBlur.outputImage
        }

        final func applyLensEffect(top: CGFloat?, bottom: CGFloat?) -> CIImage? {
            if let top, let bottom {
                topBottomFilter(top: top, bottom: bottom)
            } else if let top {
                topMaskOnlyFilter(distance: top)
            } else if let bottom {
                bottomMaskOnlyFilter(distance: bottom)
            } else {
                nil
            }
        }
    }

#endif

#if canImport(AppKit)
    public extension NSImage {
        static func block(color: NSColor, size: CGSize) -> NSImage {
            let image = NSImage(size: size)
            image.lockFocus()
            color.drawSwatch(in: NSRect(origin: .zero, size: size))
            image.unlockFocus()
            return image
        }

        func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale _: Bool = false, singleScale _: Bool = false) -> NSImage {
            let mySizePixelWidth = size.width
            let mySizePixelHeight = size.height

            let outputImagePixelWidth = targetSize.width
            let outputImagePixelHeight = targetSize.height

            let widthRatio = outputImagePixelWidth / mySizePixelWidth
            let heightRatio = outputImagePixelHeight / mySizePixelHeight

            let ratio: CGFloat = if limitTo < 1 {
                min(widthRatio, heightRatio) * limitTo
            } else {
                max(widthRatio, heightRatio) * limitTo
            }

            let drawnImageWidthPixels = Int(mySizePixelWidth * ratio)
            let drawnImageHeightPixels = Int(mySizePixelHeight * ratio)

            let offsetX = (Int(outputImagePixelWidth) - drawnImageWidthPixels) / 2
            let offsetY = (Int(outputImagePixelHeight) - drawnImageHeightPixels) / 2

            let c = CGContext(data: nil,
                              width: Int(outputImagePixelWidth),
                              height: Int(outputImagePixelHeight),
                              bitsPerComponent: 8,
                              bytesPerRow: Int(outputImagePixelWidth) * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!
            c.interpolationQuality = .high

            let imageRef = cgImage(forProposedRect: nil, context: nil, hints: nil)!
            c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: drawnImageWidthPixels, height: drawnImageHeightPixels))
            return NSImage(cgImage: c.makeImage()!, size: targetSize)
        }

        func desaturated() async -> NSImage? {
            await Task.detached {
                guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return nil
                }
                let blackAndWhiteImage = CIImage(cgImage: cgImage).applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 0,
                    "inputContrast": 0.35,
                    "inputBrightness": -0.3
                ])

                let rep = NSCIImageRep(ciImage: blackAndWhiteImage)
                let img = NSImage(size: rep.size)
                img.addRepresentation(rep)
                return img
            }.value
        }

        convenience init?(systemName _: String) {
            self.init(systemSymbolName: "circle", accessibilityDescription: nil)
        }

        func template(with tint: NSColor) -> NSImage {
            let image = copy() as! NSImage
            image.isTemplate = false
            image.lockFocus()
            tint.set()

            let imageRect = NSRect(origin: .zero, size: image.size)
            imageRect.fill(using: .sourceAtop)
            image.unlockFocus()
            return image
        }

        static func tintedShape(systemName: String, coloured: NSColor) -> NSImage? {
            let img = NSImage(systemName: systemName)
            return img?.template(with: coloured)
        }
    }

#else

    #if canImport(WatchKit)
        private var screenScale: CGFloat {
            onlyOnMainThread {
                WKInterfaceDevice.current().screenScale
            }
        }

    #elseif os(visionOS)
        private let screenScale: CGFloat = 2

    #else
        private var screenScale: CGFloat {
            onlyOnMainThread {
                UIScreen.main.scale
            }
        }
    #endif

    public let pixelSize: CGFloat = 1 / screenScale

    public extension UIImage {
        static func fromFile(_ url: URL, template: Bool) -> UIImage? {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: template ? screenScale : 1) {
                if template {
                    return image.withRenderingMode(.alwaysTemplate)
                } else {
                    return image
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

            let widthRatio = outputImagePixelWidth / mySizePixelWidth
            let heightRatio = outputImagePixelHeight / mySizePixelHeight

            let ratio: CGFloat = if limitTo < 1 {
                min(widthRatio, heightRatio) * limitTo
            } else {
                max(widthRatio, heightRatio) * limitTo
            }

            let drawnImageWidthPixels = Int(mySizePixelWidth * ratio)
            let drawnImageHeightPixels = Int(mySizePixelHeight * ratio)

            let offsetX = (Int(outputImagePixelWidth) - drawnImageWidthPixels) / 2
            let offsetY = (Int(outputImagePixelHeight) - drawnImageHeightPixels) / 2

            let orientation = imageOrientation
            var transform: CGAffineTransform = switch orientation {
            case .down, .downMirrored:
                CGAffineTransform(translationX: outputImagePixelWidth, y: outputImagePixelHeight).rotated(by: .pi)
            case .left, .leftMirrored:
                CGAffineTransform(translationX: outputImagePixelWidth, y: 0).rotated(by: .pi / 2)
            case .right, .rightMirrored:
                CGAffineTransform(translationX: 0, y: outputImagePixelHeight).rotated(by: -.pi / 2)
            default:
                .identity
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

        #if canImport(CoreImage)

            static func block(color: UIColor, size: CGSize) -> UIImage {
                let rect = CGRect(origin: .zero, size: size)
                return UIGraphicsImageRenderer(bounds: rect).image {
                    $0.cgContext.setFillColor(color.cgColor)
                    $0.fill(rect)
                }
            }

            static func tintedShape(systemName: String, coloured: UIColor) -> UIImage? {
                let img = UIImage(systemName: systemName)
                return img?.withTintColor(coloured, renderingMode: .alwaysOriginal)
            }

            final func desaturated(darkMode: Bool) -> UIImage {
                guard let ciImage = CIImage(image: self) else {
                    return self
                }
                let p1 = darkMode ? "inputColor0" : "inputColor1"
                let p2 = darkMode ? "inputColor1" : "inputColor0"
                #if os(visionOS)
                    let a: CGFloat = 0.5
                #else
                    let a: CGFloat = darkMode ? 0.05 : 0.2
                #endif
                let blackAndWhiteImage = ciImage
                    .applyingFilter("CIFalseColor", parameters: [
                        p1: CIColor(color: .systemBackground),
                        p2: CIColor(color: .secondaryLabel.withAlphaComponent(a))
                    ])
                return blackAndWhiteImage.asImage ?? self
            }
        #endif
    }
#endif
