#if os(iOS)
    import UIKit
    typealias COLORCLASS = UIColor
#else
    import AppKit
    import Foundation
    typealias COLORCLASS = NSColor
#endif

extension COLORCLASS {
    static let g_colorComponentLabel = COLORCLASS(named: "colorComponentLabel")!
    static let g_colorDarkGray = COLORCLASS(named: "colorDarkGray")!
    static let g_colorDim = COLORCLASS(named: "colorDim")!
    static let g_colorFill = COLORCLASS(named: "colorFill")!
    static let g_colorGray = COLORCLASS(named: "colorGray")!
    static let g_colorKeyboardBright = COLORCLASS(named: "colorKeyboardBright")!
    static let g_colorKeyboardGray = COLORCLASS(named: "colorKeyboardGray")!
    static let g_colorLightGray = COLORCLASS(named: "colorLightGray")!
    static let g_colorMacCard = COLORCLASS(named: "colorMacCard")!
    static let g_colorPaper = COLORCLASS(named: "colorPaper")!
    static let g_colorShadow = COLORCLASS(named: "colorShadow")!
    static let g_colorShadowContrast = COLORCLASS(named: "colorShadowContrast")!
    static let g_colorTint = COLORCLASS(named: "colorTint")!
    static let g_sectionTitleTop = COLORCLASS(named: "sectionTitleTop")!
    static let g_sectionTitleBottom = COLORCLASS(named: "sectionTitleBottom")!
    static let g_expandedSection = COLORCLASS(named: "colorExpandedSection")!
}
