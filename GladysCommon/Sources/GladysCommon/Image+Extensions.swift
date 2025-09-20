import Foundation
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(UIKit)
    import UIKit
#endif

#if canImport(WatchKit)
    import WatchKit
#endif

#if canImport(CoreImage)
    import CoreImage
    import CoreImage.CIFilterBuiltins
#endif

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
    @concurrent static func from(data: Data) async -> IMAGE? {
        IMAGE(data: data)
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
            guard let cgi = getCgImage() else { return nil }

            return CIImage(cgImage: cgi, options: [.nearestSampling: true])
        }
    #endif

    func getCgImage() -> CGImage? {
        #if canImport(AppKit)
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
            cgImage
        #endif
    }

    @concurrent final func calculateOuterColor(size: CGSize, top: Bool?, rawData: UnsafeMutableRawBufferPointer) async -> COLOR? {
        guard let cgi = getCgImage() else { return nil }
        let wholeWidth = cgi.width
        let wholeHeight = cgi.height
        if wholeWidth <= 0 || wholeHeight <= 0 {
            return nil
        }

        let edgeInsetH: CGFloat = 50
        let edgeInsetV: CGFloat = 10
        let H: CGFloat = 24
        let total = edgeInsetH + H
        let sampleRect: CGRect

        if let top, size.width > total, size.height > total {
            let W = size.width - edgeInsetH * 2
            let sampleSize = CGSize(width: W, height: H)
            if top {
                sampleRect = CGRect(origin: CGPoint(x: edgeInsetH, y: edgeInsetV), size: sampleSize)
            } else {
                sampleRect = CGRect(origin: CGPoint(x: edgeInsetH, y: size.height - edgeInsetV - H), size: sampleSize)
            }
        } else {
            sampleRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }

        #if canImport(AppKit)
            let scale: CGFloat = 1
        #endif

        let bytesPerRow = cgi.width * 4

        let scanOriginX = Int(sampleRect.origin.x * scale)
        let scanWidth = Int(sampleRect.width * scale)

        let scanOriginY = Int(sampleRect.origin.y * scale)
        let scanHeight = Int(sampleRect.height * scale)

        var rt = 0
        var bt = 0
        var gt = 0
        var at = 0

        for y in stride(from: scanOriginY, to: scanOriginY + scanHeight, by: 2) {
            for x in stride(from: scanOriginX, to: scanOriginX + scanWidth, by: 2) {
                var i = x * 4 + (y * bytesPerRow)
                at += Int(rawData[i])
                i += 1
                rt += Int(rawData[i])
                i += 1
                gt += Int(rawData[i])
                i += 1
                bt += Int(rawData[i])
            }
        }

        let numberOfPixels = CGFloat(scanWidth * scanHeight * 255)
        let a = CGFloat(at) / numberOfPixels
        let r = CGFloat(rt) / numberOfPixels
        let g = CGFloat(gt) / numberOfPixels
        let b = CGFloat(bt) / numberOfPixels

        #if canImport(AppKit)
            return COLOR(srgbRed: r, green: g, blue: b, alpha: a)
        #else
            return COLOR(red: r, green: g, blue: b, alpha: a)
        #endif
    }
}

#if canImport(CoreImage)

    private final actor CIBuffer {
        private var ciQueue = [CIContext]()

        init() {}

        func getContext() async -> CIContext {
            if let next = ciQueue.popLast() {
                return next
            }
            let cgContext = createCgContext(width: 1, height: 1)
            return CIContext(cgContext: cgContext, options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
        }

        func returnContext(_ context: CIContext) {
            ciQueue.append(context)
        }
    }

    private let ciBuffer = CIBuffer()

    private let sharedCiContext = CIContext(options: [.cacheIntermediates: false])

    public extension CIImage {
        var asImage: IMAGE? {
            guard let new = sharedCiContext.createCGImage(self, from: extent) else {
                return nil
            }
            #if canImport(AppKit)
                return IMAGE(cgImage: new, size: CGSize(width: 512, height: 512))
            #else
                return IMAGE(cgImage: new)
            #endif
        }

        private func topGradientFilterImage(distance: CGFloat) -> CIImage? {
            let greenClear = CIColor(red: 0, green: 1, blue: 0, alpha: 0)
            let greenOpaque = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
            let height = extent.height
            let unitDistanceClear = distance * height
            let unitDistanceOpaque = (distance - 0.2) * height

            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: 0, y: height - unitDistanceClear)
            gradient.color0 = greenClear
            gradient.point1 = CGPoint(x: 0, y: height - unitDistanceOpaque)
            gradient.color1 = greenOpaque
            return gradient.outputImage
        }

        private func bottomGradientFilterImage(distance: CGFloat) -> CIImage? {
            let greenClear = CIColor(red: 0, green: 1, blue: 0, alpha: 0)
            let greenOpaque = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
            let height = extent.height
            let unitDistanceClear = distance * height
            let unitDistanceOpaque = (distance - 0.2) * height

            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: 0, y: unitDistanceOpaque)
            gradient.color0 = greenOpaque
            gradient.point1 = CGPoint(x: 0, y: unitDistanceClear)
            gradient.color1 = greenClear
            return gradient.outputImage
        }

        private func createMaskedVariableBlur(mask: CIImage?) -> CIFilter & CIMaskedVariableBlur {
            let maskedVariableBlur = CIFilter.maskedVariableBlur()
            maskedVariableBlur.inputImage = self
            maskedVariableBlur.radius = 8
            maskedVariableBlur.mask = mask
            return maskedVariableBlur
        }

        private func topMaskOnlyFilter(distance: CGFloat) -> CIImage? {
            createMaskedVariableBlur(mask: topGradientFilterImage(distance: distance)).outputImage
        }

        private func bottomMaskOnlyFilter(distance: CGFloat) -> CIImage? {
            createMaskedVariableBlur(mask: bottomGradientFilterImage(distance: distance)).outputImage
        }

        private func topBottomFilter(top: CGFloat, bottom: CGFloat) -> CIImage? {
            let gradientMask = CIFilter.additionCompositing()
            gradientMask.inputImage = topGradientFilterImage(distance: top)
            gradientMask.backgroundImage = bottomGradientFilterImage(distance: bottom)

            return createMaskedVariableBlur(mask: gradientMask.outputImage).outputImage
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

private let bitmapInfo = CGBitmapInfo(alpha: .premultipliedFirst, component: .integer, byteOrder: .orderDefault)
private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
public func createCgContext(data: UnsafeMutableRawPointer? = nil, width: Int, height _: Int) -> CGContext {
    CGContext(data: data,
              width: width,
              height: width,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: srgb,
              bitmapInfo: bitmapInfo)!
}

#if canImport(AppKit)
    public extension NSImage {
        static func block(color: NSColor, size: CGSize) -> NSImage {
            let image = NSImage(size: size)
            image.lockFocus()
            color.drawSwatch(in: NSRect(origin: .zero, size: size))
            image.unlockFocus()
            return image
        }

        @concurrent final func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale _: Bool = false, singleScale _: Bool = false) async -> NSImage {
            let mySizePixelWidth = size.width
            let mySizePixelHeight = size.height
            let outputImagePixelWidth = targetSize.width
            let outputImagePixelHeight = targetSize.height

            if mySizePixelWidth <= 0 || mySizePixelHeight <= 0 || outputImagePixelWidth <= 0 || outputImagePixelHeight <= 0 {
                return NSImage()
            }

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

            let c = createCgContext(width: Int(outputImagePixelWidth), height: Int(outputImagePixelHeight))
            c.interpolationQuality = .high

            let imageRef = cgImage(forProposedRect: nil, context: nil, hints: nil)!
            c.draw(imageRef, in: CGRect(x: offsetX, y: offsetY, width: drawnImageWidthPixels, height: drawnImageHeightPixels))
            return NSImage(cgImage: c.makeImage()!, size: targetSize)
        }

        @concurrent func desaturated() async -> NSImage? {
            guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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
        @MainActor
        private let screenScale: CGFloat = WKInterfaceDevice.current().screenScale

    #else
        #if os(visionOS)
            private let screenScale: CGFloat = 2
        #else
            @MainActor
            private var screenScale: CGFloat {
                UIScreen.main.scale
            }
        #endif
    #endif

    @MainActor
    public let pixelSize: CGFloat = 1 / screenScale

    public extension UIImage {
        @MainActor
        static func fromFileSync(_ url: URL, template: Bool) -> UIImage? {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: template ? screenScale : 1) {
                if template {
                    return image.withRenderingMode(.alwaysTemplate)
                } else {
                    return image
                }
            }
            return nil
        }

        @concurrent static func fromFile(_ url: URL, template: Bool) async -> UIImage? {
            if let data = try? Data(contentsOf: url), let image = await UIImage(data: data, scale: template ? screenScale : 1) {
                if template {
                    return image.withRenderingMode(.alwaysTemplate)
                } else {
                    return image
                }
            }
            return nil
        }

        @concurrent final func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale: Bool = false, singleScale: Bool = false) async -> UIImage {
            guard let cgImage else {
                return UIImage()
            }

            let targetScale = singleScale ? 1 : scale
            let mySizePixelWidth = size.width * targetScale
            let mySizePixelHeight = size.height * targetScale

            let effectiveScale = if useScreenScale {
                await screenScale
            } else {
                targetScale
            }
            let outputImagePixelWidth = targetSize.width * effectiveScale
            let outputImagePixelHeight = targetSize.height * effectiveScale

            if mySizePixelWidth <= 0 || mySizePixelHeight <= 0 || outputImagePixelWidth <= 0 || outputImagePixelHeight <= 0 {
                return UIImage()
            }

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

            let c = createCgContext(width: Int(outputImagePixelWidth), height: Int(outputImagePixelHeight))
            c.interpolationQuality = .high
            c.concatenate(transform)

            switch orientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                c.draw(cgImage, in: CGRect(x: offsetY, y: offsetX, width: drawnImageHeightPixels, height: drawnImageWidthPixels))
            default:
                c.draw(cgImage, in: CGRect(x: offsetX, y: offsetY, width: drawnImageWidthPixels, height: drawnImageHeightPixels))
            }

            guard let createdCgImage = c.makeImage() else {
                return UIImage()
            }

            return UIImage(cgImage: createdCgImage, scale: effectiveScale, orientation: .up)
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
