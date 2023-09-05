import Foundation
import GladysCommon
import SwiftUI

#if os(visionOS)
    private let tagFont = FONT.TextStyle.body
#else
    private let tagFont = FONT.TextStyle.caption2
#endif

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

            let ls = labels.map { $0.replacingOccurrences(of: " ", with: "\u{a0}") }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: FONT.preferredFont(forTextStyle: tagFont),
                .foregroundColor: labelTextColor,
                .paragraphStyle: p
            ]
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: FONT.preferredFont(forTextStyle: tagFont),
                .foregroundColor: labelTextColor,
                .paragraphStyle: p,
                TokenField.highlightTextKey: true
            ]
            let string = NSMutableAttributedString(string: "", attributes: attrs)
            let sep = NSMutableAttributedString(string: TokenField.separator, attributes: attrs)

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

    private var xInset: CGFloat {
        TagCloudView.margin + (alignment == .center ? 0 : 3.5)
    }

    override func draw(_ rect: CGRect) {
        #if canImport(AppKit)
            guard let frameSetter, let context = NSGraphicsContext.current?.cgContext else { return }
        #else
            guard let frameSetter, let context = UIGraphicsGetCurrentContext() else { return }
        #endif

        let dirtyRect = rect.insetBy(dx: xInset, dy: 0)

        let path = CGPath(rect: dirtyRect, transform: nil)
        let totalFrame = CTFramesetterCreateFrame(frameSetter, TokenField.emptyRange, path, nil)

        #if canImport(AppKit)
            context.translateBy(x: 0, y: -1)
        #else
            context.translateBy(x: 0, y: dirtyRect.height + 1)
            context.scaleBy(x: 1, y: -1)
        #endif

        let lines = CTFrameGetLines(totalFrame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(totalFrame, TokenField.emptyRange, &origins)
        let key = unsafeBitCast(TokenField.highlightTextKey, to: UnsafeRawPointer.self)

        for (line, linePos) in zip(lines, origins) {
            let lineBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            let lineStart = alignment == .center ? (dirtyRect.width - lineBounds.width) * 0.5 : (lineBounds.minX + 4)

            let runs = CTLineGetGlyphRuns(line)
            for i in 0 ..< CFArrayGetCount(runs) {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
                let attributes = CTRunGetAttributes(run)
                guard CFDictionaryContainsKey(attributes, key) else {
                    continue
                }

                #if os(visionOS)
                    let x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil) - 6
                    let w = CGFloat(CTRunGetImageBounds(run, context, TokenField.emptyRange).width) + 17
                    let h = lineBounds.height + 2
                    let y = linePos.y - 6.5
                #else
                    let x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil) - 3.5
                    let w = CGFloat(CTRunGetImageBounds(run, context, TokenField.emptyRange).width) + 12
                    let h = lineBounds.height + 2
                    let y = linePos.y - 4
                #endif

                let corner = (h * 0.5).rounded(.down)
                context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
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
        let guide = CGSize(width: cellWidth - (xInset * 2), height: CGFLOAT_MAX)
        var result = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, TokenField.emptyRange, nil, guide, nil)
        result.width += 2
        result.height += 2
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

    static let margin: CGFloat = 2

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
