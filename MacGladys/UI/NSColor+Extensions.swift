import Cocoa
import CoreImage

extension NSColor {
    var hexValue: String {
        guard let convertedColor = usingColorSpace(.deviceRGB) else { return "#000000" }
        var redFloatValue: CGFloat = 0, greenFloatValue: CGFloat = 0, blueFloatValue: CGFloat = 0
        convertedColor.getRed(&redFloatValue, green: &greenFloatValue, blue: &blueFloatValue, alpha: nil)
        let r = Int(redFloatValue * 255.99999)
        let g = Int(greenFloatValue * 255.99999)
        let b = Int(blueFloatValue * 255.99999)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension NSImage {
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
}
