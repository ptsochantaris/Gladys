//
//  NSColor+Extensions.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 19/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import CoreImage

extension NSColor {
	var hexValue: String {
		guard let convertedColor = usingColorSpaceName(.calibratedRGB) else { return "#000000"}
		var redFloatValue: CGFloat = 0, greenFloatValue: CGFloat = 0, blueFloatValue: CGFloat = 0
		convertedColor.getRed(&redFloatValue, green: &greenFloatValue, blue: &blueFloatValue, alpha: nil)
		let r = Int(redFloatValue * 255.99999)
		let g = Int(greenFloatValue * 255.99999)
		let b = Int(blueFloatValue * 255.99999)
		return String(format: "#%02X%02X%02X", r, g, b)
	}
}

extension NSImage {
    func desaturated(completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let blackAndWhiteImage = CIImage(cgImage: cgImage).applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 0,
                "inputContrast": 0.35,
                "inputBrightness": -0.3])
                        
            let rep = NSCIImageRep(ciImage: blackAndWhiteImage)
            let img = NSImage(size: rep.size)
            img.addRepresentation(rep)
            DispatchQueue.main.async {
                completion(img)
            }
        }
    }
}
