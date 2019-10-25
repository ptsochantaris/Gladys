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

	static let highlightTextKey = NSAttributedString.Key("HighlightText")

	private func update() {

		if labels.isEmpty {
			attributedText = nil
			return
		}

		guard let font = font, let tintColor = tintColor else {
			return
		}

		let p = NSMutableParagraphStyle()
		p.alignment = textAlignment
		p.lineBreakMode = .byWordWrapping
		p.lineHeightMultiple = 1.3

		if textAlignment == .natural {
			p.firstLineHeadIndent = 4
			p.headIndent = 3
		}

		let separator = "   "

		let string = NSMutableAttributedString(string: labels.joined(separator: separator), attributes: [
			.font: font,
			.foregroundColor: tintColor,
			.paragraphStyle: p,
			.baselineOffset: 1,
			])

		var start = 0
		for label in labels {
			let len = label.count
			string.addAttribute(HighlightLabel.highlightTextKey, value: 1, range: NSMakeRange(start, len))
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
		let leftAlign = textAlignment == .natural

		for index in 0 ..< lineCount {
			let line = lines[index] as! CTLine

			var origins = [CGPoint](repeating: .zero, count: lineCount)
			CTFrameGetLineOrigins(totalFrame, CFRangeMake(0, 0), &origins)
            let lineFrame = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
			let lineStart = leftAlign ? 4 : (bounds.width - lineFrame.width) * 0.5

			for r in CTLineGetGlyphRuns(line) as NSArray {

				let run = r as! CTRun
				let attributes = CTRunGetAttributes(run) as NSDictionary

				if attributes["HighlightText"] != nil {
					var runBounds = lineFrame

                    runBounds.size.width = CGFloat(CTRunGetImageBounds(run, context, CFRangeMake(0, 0)).width) + 8
                    runBounds.origin.x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil) - 3.5
                    runBounds.origin.y = origins[index].y - 3
                    runBounds.size.height += 1

					context.addPath(CGPath(roundedRect: runBounds, cornerWidth: 3, cornerHeight: 3, transform: nil))
				}
			}
		}

		context.setStrokeColor(highlightColor.withAlphaComponent(0.7).cgColor)
		context.setLineWidth(0.5)
		context.strokePath()
	}
}
