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

	override var tintColor: UIColor! {
		didSet {
			if oldValue != tintColor {
				update()
			}
		}
	}

	private func update() {

		if labels.isEmpty {
			attributedText = nil
			return
		}

		let p = NSMutableParagraphStyle()
		p.alignment = textAlignment
		p.lineBreakMode = .byWordWrapping
		p.lineHeightMultiple = 1.3

		let separator = "   "

		let string = NSMutableAttributedString(string: labels.joined(separator: separator), attributes: [
			.font: font,
			.foregroundColor: tintColor!,
			.paragraphStyle: p,
			.baselineOffset: 1,
			])

		var start = 0
		for label in labels {
			let len = label.count
			string.addAttribute(NSAttributedString.Key("HighlightText"), value: 1, range: NSMakeRange(start, len))
			start += len + separator.count
		}
		attributedText = string
	}

	override func draw(_ rect: CGRect) {

		guard let attributedText = attributedText, let highlightColor = tintColor, !attributedText.string.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }

		let framesetter = CTFramesetterCreateWithAttributedString(attributedText)

		let totalFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil)

		context.textMatrix = .identity
		context.translateBy(x: 0, y: bounds.size.height)
		context.scaleBy(x: 1, y: -1)

		CTFrameDraw(totalFrame, context)

		// frames

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

					context.addPath(CGPath(roundedRect: runBounds, cornerWidth: 3, cornerHeight: 3, transform: nil))
				}
			}
		}

		context.setStrokeColor(highlightColor.withAlphaComponent(0.7).cgColor)
		context.setLineWidth(0.5)
		context.strokePath()
	}
}
