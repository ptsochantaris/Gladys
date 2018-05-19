//
//  NSColor+Extensions.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 19/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

extension NSColor {
	var hexValue: String {
		guard let convertedColor = usingColorSpaceName(.calibratedRGB) else { return "#000000"}
		var redFloatValue:CGFloat = 0.0, greenFloatValue:CGFloat = 0.0, blueFloatValue:CGFloat = 0.0
		convertedColor.getRed(&redFloatValue, green: &greenFloatValue, blue: &blueFloatValue, alpha: nil)
		let r = Int(redFloatValue * 255.99999)
		let g = Int(greenFloatValue * 255.99999)
		let b = Int(blueFloatValue * 255.99999)
		return String(format: "#%02X%02X%02X", r, g, b)
	}
}
