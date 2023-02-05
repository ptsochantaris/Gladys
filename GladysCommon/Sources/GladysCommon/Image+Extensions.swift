#if os(macOS)
    import Cocoa
#elseif os(iOS)
    import UIKit
#elseif os(watchOS)
    import WatchKit
#endif
import Foundation

public extension IMAGE {
    static func from(data: Data) async -> IMAGE? {
        await Task.detached {
            IMAGE(data: data)
        }.value
    }
}

#if os(macOS)
    public extension NSImage {
        func limited(to targetSize: CGSize, limitTo: CGFloat = 1.0, useScreenScale _: Bool = false, singleScale _: Bool = false) -> NSImage {
            let mySizePixelWidth = size.width
            let mySizePixelHeight = size.height

            let outputImagePixelWidth = targetSize.width
            let outputImagePixelHeight = targetSize.height

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

#elseif os(watchOS)
    public let screenScale = WKInterfaceDevice.current().screenScale
    public let pixelSize: CGFloat = 1 / screenScale

#elseif os(iOS)

    public let screenScale = UIScreen.main.scale
    public let pixelSize: CGFloat = 1 / screenScale

    extension UIImage {
        public static func tintedShape(systemName: String, coloured: UIColor) -> UIImage? {
            let img = UIImage(systemName: systemName)
            return img?.withTintColor(coloured, renderingMode: .alwaysOriginal)
        }

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

        private static let sharedCiContext = CIContext()

        public final func desaturated(darkMode: Bool) async -> UIImage {
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
#endif

#if os(iOS) || os(watchOS)
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
    }
#endif
