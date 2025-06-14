import Foundation
import GladysCommon
import SwiftUI

extension ItemView {
    struct SquareContentView: View {
        let wrapper: ArchivedItemWrapper

        public var body: some View {
            ZStack {
                Color(PresentationInfo.defaultCardColor)

                if wrapper.locked || wrapper.displayMode == .center {
                    Rectangle()
                        .foregroundStyle(.ultraThinMaterial)
                }

                if wrapper.status?.shouldDisplayLoading ?? true {
                    LoadingItem(wrapper: wrapper)
                        .foregroundColor(.accentColor)

                } else {
                    let size = wrapper.cellSize

                    ItemImage(wrapper: wrapper)
                        .foregroundColor(.accentColor)
                        .frame(width: size.width, height: size.height)

                    SquareItemText(wrapper: wrapper)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
    }

    private struct SquareItemText: View {
        let wrapper: ArchivedItemWrapper

        var body: some View {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    SquareLabel(wrapper: wrapper, atTop: true)
                    Spacer(minLength: 0)
                    SquareLabel(wrapper: wrapper, atTop: false)
                }
                .frame(maxWidth: .infinity)

                SelectionTick(wrapper: wrapper)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(titleFont)
            .frame(width: wrapper.cellSize.width)
        }
    }

    private struct SquareLabel: View {
        let wrapper: ArchivedItemWrapper
        @Environment(\.colorScheme) var colorScheme

        private let showLabels: Bool
        private let lineLimit: Int
        private let contentText: String
        private let highlight: Bool
        private let atTop: Bool
        private let fadeColor: Color

        init(wrapper: ArchivedItemWrapper, atTop: Bool) {
            self.wrapper = wrapper
            self.atTop = atTop

            let presentation = wrapper.presentationInfo
            let info = atTop ? presentation.top.content : presentation.bottom.content
            lineLimit = info.lineLimit(isTop: atTop, size: PresentationInfo.labelSize(for: presentation.cellSize))
            switch info {
            case let .hint(hintText):
                contentText = hintText
                showLabels = false
                highlight = true
            case let .link(url):
                contentText = url.absoluteString
                showLabels = !atTop && wrapper.style.allowsLabels
                highlight = false
            case .none:
                contentText = ""
                showLabels = !atTop && wrapper.style.allowsLabels
                highlight = false
            case let .note(text):
                contentText = text
                showLabels = !atTop && wrapper.style.allowsLabels
                highlight = true
            case let .text(text):
                contentText = text
                showLabels = !atTop && wrapper.style.allowsLabels
                highlight = false
            }

            if wrapper.displayMode != .center, !wrapper.locked, presentation.image != nil, !presentation.hasTransparentBackground {
                fadeColor = atTop ? presentation.top.backgroundColor : presentation.bottom.backgroundColor
            } else {
                #if os(visionOS)
                    fadeColor = .clear
                #else
                    fadeColor = Color(PresentationInfo.defaultCardColor)
                #endif
            }
        }

        @ViewBuilder
        private func createTextView() -> (some View)? {
            if contentText.isPopulated {
                let info = wrapper.presentationInfo
                let fgColor: Color = if highlight {
                    info.hasTransparentBackground ? .accentColor : ((colorScheme == .dark || info.bottom.isBright) ? .accentColor : .white)
                } else if info.hasTransparentBackground {
                    .primary
                } else {
                    (atTop ? info.top.isBright : info.bottom.isBright) ? .black : .white
                }
                Text(contentText)
                    .foregroundColor(fgColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit)
                    .shadow(color: fadeColor, radius: 3, x: 0, y: 0)
            }
        }

        @ViewBuilder
        private func createShareView() -> (some View)? {
            if !atTop, let shareInfo = wrapper.createShareInfo() {
                HStack(spacing: 4) {
                    Image(systemName: shareInfo.imageName)
                    Text(shareInfo.labelText)
                }
                .foregroundColor(.accentColor)
            }
        }

        var body: some View {
            let cellSize = wrapper.cellSize
            let labels = showLabels ? wrapper.createLabelView(width: cellSize.width - 8, alignment: .center) : nil
            let textView = createTextView()
            let shareView = createShareView()

            if textView != nil || shareView != nil || labels != nil {
                VStack(alignment: .center, spacing: wrapper.labelSpacing) {
                    labels
                    textView
                    shareView
                }
                .padding(PresentationInfo.labelPadding(compact: cellSize.isCompact))
                .frame(maxWidth: .infinity)
                .background {
                    if wrapper.style == .widget {
                        GradientBackgroundWeak(fadeColor: fadeColor, atTop: atTop)
                    } else {
                        GradientBackgroundStrong(fadeColor: fadeColor, atTop: atTop)
                    }
                }
            }
        }
    }
}
