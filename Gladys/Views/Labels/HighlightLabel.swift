//
//  HighlightLabel.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 13/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CoreText
import UIKit

final class HighlightLabel: UILabel {
    private var _labels = [String]()
    var labels: [String] {
        get {
            _labels
        }
        set {
            let l = newValue.map { $0.replacingOccurrences(of: " ", with: "\u{a0}") }
            if _labels != l {
                _labels = l
                cachedPath = nil
                update()
            }
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
    private static let separator = "   "
    private static let separatorCount = separator.utf16.count

    private func update() {
        let ls = _labels

        guard !ls.isEmpty, let font = font, let tintColor = tintColor else {
            attributedText = nil
            return
        }

        let p = NSMutableParagraphStyle()
        p.alignment = textAlignment
        p.lineBreakMode = .byWordWrapping
        p.lineHeightMultiple = 1.3

        if textAlignment == .natural {
            p.firstLineHeadIndent = 4
            p.headIndent = 4
        } else {
            p.headIndent = 4
            p.firstLineHeadIndent = 4
            p.tailIndent = -4
        }

        let joinedLabels = ls.joined(separator: HighlightLabel.separator)
        let string = NSMutableAttributedString(string: joinedLabels, attributes: [
            .font: font,
            .foregroundColor: tintColor,
            .paragraphStyle: p,
            .baselineOffset: 1
        ])

        var start = 0
        for label in ls {
            let len = label.utf16.count
            string.addAttribute(HighlightLabel.highlightTextKey, value: 1, range: NSRange(location: start, length: len))
            start += len + HighlightLabel.separatorCount
        }
        attributedText = string
    }

    private var cachedPath: CGPath?
    private var cachedSize = CGSize.zero

    override func draw(_ rect: CGRect) {
        guard !rect.isEmpty, let attributedText = attributedText, let highlightColor = tintColor, !attributedText.string.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)

        let totalFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil)

        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.size.height)
        context.scaleBy(x: 1, y: -1)

        CTFrameDraw(totalFrame, context)

        let currentSize = rect.size

        if cachedPath == nil || cachedSize != currentSize {
            let newPath = CGMutablePath()
            let lines = CTFrameGetLines(totalFrame) as! [CTLine]
            let lineCount = lines.count
            let leftAlign = textAlignment == .natural

            var origins = [CGPoint](repeating: .zero, count: lineCount)
            CTFrameGetLineOrigins(totalFrame, CFRangeMake(0, 0), &origins)

            var lineIndex = 0
            for line in lines {
                let lineFrame = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
                let lineStart = leftAlign ? 4 : (bounds.width - lineFrame.width) * 0.5

                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary

                    if attributes["HighlightText"] != nil {
                        var runBounds = lineFrame

                        runBounds.size.width = CGFloat(CTRunGetImageBounds(run, context, CFRangeMake(0, 0)).width) + 8
                        runBounds.origin.x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil) - 3.5
                        runBounds.origin.y = origins[lineIndex].y - 2.5
                        runBounds.size.height += 1

                        let path = CGPath(roundedRect: runBounds, cornerWidth: 3, cornerHeight: 3, transform: nil)
                        newPath.addPath(path)
                    }
                }
                lineIndex += 1
            }
            cachedSize = currentSize
            cachedPath = newPath
        }

        context.setLineWidth(pixelSize)
        context.setStrokeColor(highlightColor.withAlphaComponent(0.7).cgColor)
        context.addPath(cachedPath!)
        context.strokePath()
    }
}
