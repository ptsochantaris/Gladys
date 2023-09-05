import SwiftUI

public extension COLOR {
    static let g_colorComponentLabel = COLOR(named: "colorComponentLabel")!
    static let g_colorComponentLabelInverse = COLOR(named: "colorComponentLabelInverse")!
    static let g_colorKeyboardBright = COLOR(named: "colorKeyboardBright")!
    static let g_colorKeyboardGray = COLOR(named: "colorKeyboardGray")!
    static let g_colorLightGray = COLOR(named: "colorLightGray")!
    static let g_colorMacCard = COLOR(named: "colorMacCard")!
    static let g_colorPaper = COLOR(named: "colorPaper")!
    static let g_colorTint = COLOR(named: "colorTint")!
    static let g_sectionTitleTop = COLOR(named: "sectionTitleTop")!
    static let g_sectionTitleBottom = COLOR(named: "sectionTitleBottom")!
    static let g_expandedSection = COLOR(named: "colorExpandedSection")!

    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
            guard let convertedColor = usingColorSpace(.deviceRGB) else { return (0, 0, 0, 0) }
            convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
            getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }

    var hexValue: String {
        let (r1, g1, b1, _) = components
        let r = Int(r1 * 255.99999)
        let g = Int(g1 * 255.99999)
        let b = Int(b1 * 255.99999)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
