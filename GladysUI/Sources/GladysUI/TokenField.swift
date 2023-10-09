import Foundation
import GladysCommon
import SwiftUI

final class TokenField: VIEWCLASS {
    private static let highlightTextKey = NSAttributedString.Key("HT")
    private static let separator = "     "
    private static let separatorCount = separator.utf16.count
    private static let emptyRange = CFRangeMake(0, 0)

    private var frameSetter: CTFramesetter?
    private let cellWidth: CGFloat
    private let alignment: NSTextAlignment

    init(cellWidth: CGFloat, alignment: NSTextAlignment) {
        self.cellWidth = cellWidth
        self.alignment = alignment
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var labels: [String] = [] {
        didSet {
            defer {
                Task {
                    #if canImport(AppKit)
                        setNeedsDisplay(bounds)
                    #else
                        setNeedsDisplay()
                    #endif
                }
            }

            if labels.isEmpty {
                frameSetter = nil
                return
            }

            if labels == oldValue {
                return
            }

            let p = NSMutableParagraphStyle()
            p.alignment = alignment
            p.lineBreakMode = .byWordWrapping
            p.lineSpacing = 6

            #if os(visionOS)
                let labelTextColor = UIColor.white
            #else
                let labelTextColor = COLOR.g_colorMacCard
            #endif

            let font = FONT.systemFont(ofSize: FONT.smallSystemFontSize, weight: .medium)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: labelTextColor,
                .paragraphStyle: p
            ]
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: labelTextColor,
                .paragraphStyle: p,
                TokenField.highlightTextKey: true
            ]
            let string = NSMutableAttributedString(string: "", attributes: attrs)
            let sep = NSMutableAttributedString(string: TokenField.separator, attributes: attrs)

            let ls = labels.map { $0.replacingOccurrences(of: " ", with: "\u{a0}") }
            let count = ls.count - 1
            for label in ls.enumerated() {
                let l = NSAttributedString(string: label.element, attributes: labelAttrs)
                string.append(l)
                if label.offset < count {
                    string.append(sep)
                }
            }
            frameSetter = CTFramesetterCreateWithAttributedString(string)
            invalidateIntrinsicContentSize()
        }
    }

    #if canImport(AppKit)
        private static let tagPadding: CGFloat = 14
    #elseif os(visionOS)
        private static let tagPadding: CGFloat = 17
    #else
        private static let tagPadding: CGFloat = 15
    #endif
    private static let padding: CGFloat = 5

    #if canImport(AppKit)
        private static let heightInset: CGFloat = 2.5
    #else
        private static let heightInset: CGFloat = 2.5
    #endif

    override func draw(_: CGRect) {
        #if canImport(AppKit)
            guard let frameSetter, let context = NSGraphicsContext.current?.cgContext else { return }
        #else
            guard let frameSetter, let context = UIGraphicsGetCurrentContext() else { return }
        #endif

        let rect = bounds

        // context.setFillColor(NSColor.red.cgColor)
        // context.fill([rect])

        #if canImport(AppKit)
            let dirtyRect = rect.insetBy(dx: TokenField.padding, dy: 0)
        #else
            let dirtyRect = rect.insetBy(dx: TokenField.padding, dy: 0)
        #endif
        // context.setFillColor(NSColor.green.cgColor)
        // context.fill([dirtyRect])

        let path = CGPath(rect: dirtyRect, transform: nil)
        let totalFrame = CTFramesetterCreateFrame(frameSetter, TokenField.emptyRange, path, nil)

        #if canImport(AppKit)
            let nudge: CGFloat = 0.75
            context.translateBy(x: 0, y: -1)
        #else
            let nudge: CGFloat = 0.5
            context.translateBy(x: 0, y: dirtyRect.height + 1.5)
            context.scaleBy(x: 1, y: -1)
        #endif

        let lines = CTFrameGetLines(totalFrame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(totalFrame, TokenField.emptyRange, &origins)
        let key = unsafeBitCast(TokenField.highlightTextKey, to: UnsafeRawPointer.self)

        let maxLineHeight = lines.map { CTLineGetBoundsWithOptions($0, .useOpticalBounds).height }.max() ?? 10
        let lineHeight = (maxLineHeight + TokenField.heightInset).rounded(.up)
        let corner = (lineHeight * 0.5)

        for (line, linePos) in zip(lines, origins) {
            let lineLeft = linePos.x + dirtyRect.minX - TokenField.tagPadding * 0.5 + nudge

            let runs = CTLineGetGlyphRuns(line)
            for i in 0 ..< CFArrayGetCount(runs) {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
                let attributes = CTRunGetAttributes(run)
                guard CFDictionaryContainsKey(attributes, key) else {
                    continue
                }

                let bw = CTRunGetImageBounds(run, context, TokenField.emptyRange).width
                let w = CGFloat(bw) + TokenField.tagPadding
                let x = lineLeft + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil)
                #if canImport(AppKit)
                    let y = linePos.y - 4
                #else
                    let y = linePos.y - 4.5
                #endif

                context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: lineHeight),
                                       cornerWidth: corner,
                                       cornerHeight: corner,
                                       transform: nil))
            }
        }

        #if canImport(AppKit)
            context.setFillColor(COLOR.controlAccentColor.cgColor)
        #elseif os(visionOS)
            context.setFillColor(COLOR.darkGray.cgColor)
        #else
            context.setFillColor(tintColor.cgColor)
        #endif
        context.fillPath()

        CTFrameDraw(totalFrame, context)
    }

    override var intrinsicContentSize: CGSize {
        guard let frameSetter else { return .zero }
        let guide = CGSize(width: cellWidth - TokenField.tagPadding, height: CGFLOAT_MAX)
        var result = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, TokenField.emptyRange, nil, guide, nil)
        result.width += TokenField.tagPadding
        result.height += TokenField.heightInset.rounded(.up)
        return result
    }

    #if !os(macOS)
        override func tintColorDidChange() {
            super.tintColorDidChange()
            setNeedsDisplay()
        }
    #endif
}

struct TagCloudView: VRCLASS {
    @ObservedObject var wrapper: ArchivedItemWrapper
    @State var cellWidth: CGFloat
    let alignment: NSTextAlignment

    #if canImport(AppKit)
        func makeNSView(context _: Context) -> TokenField {
            TokenField(cellWidth: cellWidth, alignment: alignment)
        }

        func updateNSView(_ nsView: TokenField, context _: Context) {
            nsView.labels = wrapper.labels
        }

    #else

        func makeUIView(context _: Context) -> TokenField {
            let view = TokenField(cellWidth: cellWidth, alignment: alignment)
            view.backgroundColor = .clear
            return view
        }

        func updateUIView(_ uiView: TokenField, context _: Context) {
            uiView.labels = wrapper.labels
        }
    #endif
}
