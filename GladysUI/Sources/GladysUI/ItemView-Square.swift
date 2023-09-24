import Foundation
import GladysCommon
import SwiftUI

extension ItemView {
    struct SquareContentView: View {
        @ObservedObject var wrapper: ArchivedItemWrapper

        public var body: some View {
            ZStack {
                Color(PresentationInfo.defaultCardColor)

                if wrapper.locked || wrapper.displayMode == .center {
                    Spacer()
                        .background(.ultraThinMaterial)
                }

                if wrapper.shouldDisplayLoading {
                    LoadingItem(wrapper: wrapper)
                        .foregroundColor(.accentColor)

                } else {
                    let size = wrapper.cellSize

                    if wrapper.locked {
                        Image(systemName: "lock")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 33, height: 33)
                            .foregroundColor(.accentColor)
                    } else {
                        ItemImage(wrapper: wrapper)
                            .foregroundColor(.accentColor)
                            .frame(width: size.width, height: size.height)
                    }

                    SquareItemText(wrapper: wrapper)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
    }

    private struct SquareItemText: View {
        @ObservedObject var wrapper: ArchivedItemWrapper

        private func accessibilityText() -> String {
            var bottomText = ""
            if PersistedOptions.displayLabelsInMainView {
                let labelText = wrapper.labels.joined(separator: ", ")
                if labelText.isPopulated {
                    bottomText.append(labelText)
                }
            }
            if let bt = wrapper.presentationInfo.bottom.content.rawText {
                if bottomText.isPopulated {
                    bottomText.append("\n")
                }
                bottomText.append(bt)
            }
            return [wrapper.dominantTypeDescription, bottomText].compactMap { $0 }.joined(separator: "\n")
        }

        var body: some View {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    SquareLabel(wrapper: wrapper, atTop: true)
                    Spacer(minLength: 0)
                    SquareLabel(wrapper: wrapper, atTop: false)
                }
                .accessibilityValue(accessibilityText())
                .frame(maxWidth: .infinity)

                SelectionTick(wrapper: wrapper)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(titleFont)
            .frame(width: wrapper.cellSize.width)
        }
    }

    private struct SquareLabel: View {
        @ObservedObject var wrapper: ArchivedItemWrapper
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
            switch info {
            case let .hint(hintText):
                contentText = hintText
                showLabels = false
                lineLimit = 6
                highlight = true
            case let .link(url):
                contentText = url.absoluteString
                showLabels = !atTop && wrapper.style.allowsLabels
                lineLimit = 1
                highlight = false
            case .none:
                contentText = ""
                showLabels = !atTop && wrapper.style.allowsLabels
                lineLimit = 1
                highlight = false
            case let .note(text):
                contentText = text
                showLabels = !atTop && wrapper.style.allowsLabels
                lineLimit = 6
                highlight = true
            case let .text(text):
                contentText = text
                showLabels = !atTop && wrapper.style.allowsLabels
                lineLimit = atTop ? (wrapper.compact ? 2 : 6) : 2
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
                let hazeColor = fadeColor
                Text(contentText)
                    .fontWeight(highlight ? .semibold : .regular)
                    .foregroundColor(fgColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit)
                    .shadow(color: hazeColor, radius: 5, x: 0, y: 0)
                    .shadow(color: hazeColor, radius: 6, x: 0, y: 0)
                    .shadow(color: hazeColor, radius: 7, x: 0, y: 0)
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
            let labels = showLabels ? wrapper.createLabelView(width: wrapper.cellSize.width - 8, alignment: .center) : nil
            let textView = createTextView()
            let shareView = createShareView()

            if textView != nil || shareView != nil || labels != nil {
                #if canImport(AppKit)
                    let paddingSize: CGFloat = 10
                    let spacing: CGFloat = 4
                #else
                    let paddingSize: CGFloat = wrapper.compact ? 9 : 14
                    let spacing: CGFloat = wrapper.compact ? 4 : 5
                #endif

                VStack(alignment: .center, spacing: spacing) {
                    labels
                    textView
                    shareView
                }
                .padding(paddingSize)
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
