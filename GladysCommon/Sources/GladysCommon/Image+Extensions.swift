//
//  File.swift
//  
//
//  Created by Paul Tsochantaris on 18/01/2023.
//

import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

extension IMAGE {
    public static func from(data: Data) async -> IMAGE? {
        await Task.detached {
            IMAGE(data: data)
        }.value
    }

#if os(macOS)
    convenience public init?(systemName: String) {
        self.init(systemSymbolName: "circle", accessibilityDescription: nil)
    }
    
    public func template(with tint: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.isTemplate = false
        image.lockFocus()
        tint.set()
        
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
#endif
    
    static func tintedShape(systemName: String, coloured: COLOR) -> IMAGE? {
        let img = IMAGE(systemName: systemName)
#if os(macOS)
        return img?.template(with: coloured)
#else
        return img?.withTintColor(coloured, renderingMode: UIImage.RenderingMode.alwaysOriginal)
#endif
    }
}
