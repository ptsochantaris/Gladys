import GladysCommon
import SwiftUI

extension ItemView {
    private struct WideItemText: View {
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
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0).frame(height: 4)
                    WideLabel(wrapper: wrapper, atTop: true)
                    Spacer(minLength: 0).frame(height: 4)
                    WideLabel(wrapper: wrapper, atTop: false)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 6)
                .accessibilityValue(accessibilityText())

                SelectionTick(wrapper: wrapper)
            }
            .font(ItemView.titleFont)
        }
    }

    private struct WideLabel: View {
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
                Text(contentText)
                    .fontWeight(highlight ? .semibold : .regular)
                    .foregroundColor(highlight ? .accentColor : .primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(lineLimit)
                    .frame(minHeight: 0)
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
            let labels = showLabels ? wrapper.createLabelView(width: wrapper.cellSize.width - 96, alignment: .left) : nil
            let textView = createTextView()
            let shareView = createShareView()

            if textView != nil || shareView != nil || labels != nil {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        textView
                        labels
                        shareView
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    struct WideContentView: View {
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
                    let side = wrapper.cellSize.height
                    HStack(spacing: 0) {
                        if wrapper.locked {
                            ZStack {
                                Image(systemName: "lock")
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: 33, height: 33)
                                    .foregroundColor(.accentColor)
                            }
                            .frame(width: side, height: side)
                        } else {
                            ItemImage(wrapper: wrapper)
                                .foregroundColor(.accentColor)
                                .frame(width: side, height: side)
                        }

                        WideItemText(wrapper: wrapper)
                            .frame(width: wrapper.cellSize.width - side, height: side)
                    }
                }
            }
        }
    }
}
