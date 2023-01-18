import Cocoa

extension NSImage {
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
}
