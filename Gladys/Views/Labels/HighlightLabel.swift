//
//  HighlightLabel.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 13/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreText

final class HighlightLabel: UILabel {

	var labels = [String]() {
		didSet {
			update()
		}
	}

	override func tintColorDidChange() {
		super.tintColorDidChange()
		update()
	}

	private func update() {
		let p = NSMutableParagraphStyle()
		p.alignment = textAlignment
		p.lineBreakMode = .byWordWrapping
		p.lineHeightMultiple = 1.3

		let separator = "   "

		let string = NSMutableAttributedString(string: labels.joined(separator: separator), attributes: [
			NSAttributedStringKey.font: font,
			NSAttributedStringKey.foregroundColor: tintColor!,
			NSAttributedStringKey.paragraphStyle: p,
			NSAttributedStringKey.baselineOffset: 1,
			])

		var start = 0
		for label in labels {
			let len = label.count
			string.addAttribute(NSAttributedStringKey("HighlightText"), value: 1, range: NSMakeRange(start, len))
			start += len + separator.count
		}
		attributedText = string
		setNeedsDisplay()
	}

	override func draw(_ rect: CGRect) {

		guard let attributedText = attributedText, !attributedText.string.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }

		let highlightColor = tintColor!

		let framesetter = CTFramesetterCreateWithAttributedString(attributedText)

		let path = CGMutablePath()
		path.addRect(bounds)

		let totalFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

		context.textMatrix = .identity
		context.translateBy(x: 0, y: bounds.size.height)
		context.scaleBy(x: 1, y: -1)

		if labels.count > 0 {

			let lines = CTFrameGetLines(totalFrame) as NSArray
			let lineCount = lines.count

			for index in 0 ..< lineCount {
				let line = lines[index] as! CTLine

				var origins = [CGPoint](repeating: .zero, count: lineCount)
				CTFrameGetLineOrigins(totalFrame, CFRangeMake(0, 0), &origins)
				let lineFrame = CTLineGetBoundsWithOptions(line, [])
				let offset: CGFloat = index < (lineCount-1) ? 2 : -6
				let lineStart = (bounds.width - lineFrame.width + offset) * 0.5

				for r in CTLineGetGlyphRuns(line) as NSArray {

					let run = r as! CTRun
					let attributes = CTRunGetAttributes(run) as NSDictionary

					if attributes["HighlightText"] != nil {
						var runBounds = lineFrame

						runBounds.size.width = CGFloat(CTRunGetTypographicBounds(run, CFRangeMake(0, 0), nil, nil ,nil)) + 6
						runBounds.origin.x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil)
						runBounds.origin.y = origins[index].y - 2

						context.setStrokeColor(highlightColor.withAlphaComponent(0.7).cgColor)
						context.setLineWidth(0.5)
						context.addPath(CGPath(roundedRect: runBounds, cornerWidth: 3, cornerHeight: 3, transform: nil))
						context.strokePath()
					}
				}
			}
		}

		CTFrameDraw(totalFrame, context)
	}
}
