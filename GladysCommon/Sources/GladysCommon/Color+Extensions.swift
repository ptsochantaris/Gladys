#if os(macOS)
    import AppKit
    import Foundation
    public typealias COLORCLASS = NSColor
#else
    import UIKit
    public typealias COLORCLASS = UIColor
#endif

extension COLORCLASS {
    public static let g_colorComponentLabel = COLORCLASS(named: "colorComponentLabel")!
    public static let g_colorComponentLabelInverse = COLORCLASS(named: "colorComponentLabelInverse")!
    public static let g_colorDarkGray = COLORCLASS(named: "colorDarkGray")!
    public static let g_colorDim = COLORCLASS(named: "colorDim")!
    public static let g_colorFill = COLORCLASS(named: "colorFill")!
    public static let g_colorGray = COLORCLASS(named: "colorGray")!
    public static let g_colorKeyboardBright = COLORCLASS(named: "colorKeyboardBright")!
    public static let g_colorKeyboardGray = COLORCLASS(named: "colorKeyboardGray")!
    public static let g_colorLightGray = COLORCLASS(named: "colorLightGray")!
    public static let g_colorMacCard = COLORCLASS(named: "colorMacCard")!
    public static let g_colorPaper = COLORCLASS(named: "colorPaper")!
    public static let g_colorShadow = COLORCLASS(named: "colorShadow")!
    public static let g_colorShadowContrast = COLORCLASS(named: "colorShadowContrast")!
    public static let g_colorTint = COLORCLASS(named: "colorTint")!
    public static let g_sectionTitleTop = COLORCLASS(named: "sectionTitleTop")!
    public static let g_sectionTitleBottom = COLORCLASS(named: "sectionTitleBottom")!
    public static let g_expandedSection = COLORCLASS(named: "colorExpandedSection")!
}
