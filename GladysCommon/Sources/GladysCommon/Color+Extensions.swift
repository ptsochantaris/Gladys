#if os(macOS)
    import AppKit
    import Foundation
    public typealias COLORCLASS = NSColor
#else
    import UIKit
    public typealias COLORCLASS = UIColor
#endif

public extension COLORCLASS {
    static let g_colorComponentLabel = COLORCLASS(named: "colorComponentLabel")!
    static let g_colorComponentLabelInverse = COLORCLASS(named: "colorComponentLabelInverse")!
    static let g_colorKeyboardBright = COLORCLASS(named: "colorKeyboardBright")!
    static let g_colorKeyboardGray = COLORCLASS(named: "colorKeyboardGray")!
    static let g_colorLightGray = COLORCLASS(named: "colorLightGray")!
    static let g_colorMacCard = COLORCLASS(named: "colorMacCard")!
    static let g_colorPaper = COLORCLASS(named: "colorPaper")!
    static let g_colorTint = COLORCLASS(named: "colorTint")!
    static let g_sectionTitleTop = COLORCLASS(named: "sectionTitleTop")!
    static let g_sectionTitleBottom = COLORCLASS(named: "sectionTitleBottom")!
    static let g_expandedSection = COLORCLASS(named: "colorExpandedSection")!
}

#if os(macOS)
    public extension NSColor {
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
#else
    public extension UIColor {
        var hexValue: String {
            var redFloatValue: CGFloat = 0, greenFloatValue: CGFloat = 0, blueFloatValue: CGFloat = 0
            getRed(&redFloatValue, green: &greenFloatValue, blue: &blueFloatValue, alpha: nil)
            let r = Int(redFloatValue * 255.99999)
            let g = Int(greenFloatValue * 255.99999)
            let b = Int(blueFloatValue * 255.99999)
            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
#endif
