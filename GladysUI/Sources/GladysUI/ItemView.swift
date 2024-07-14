import Foundation
import GladysCommon
import SwiftUI

public struct ItemView: View {
    #if os(visionOS)
        nonisolated static let titleFont = Font.body
    #else
        nonisolated static let titleFont = Font.caption
    #endif

    struct LoadingItem: View {
        let wrapper: ArchivedItemWrapper

        var body: some View {
            if case let .isBeingIngested(loadingProgress) = wrapper.status, let progress = loadingProgress?.fractionCompleted {
                VStack(spacing: 20) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())

                    Button(action: {
                        wrapper.delete()
                    }, label: {
                        Text("Cancel")
                    })
                }
                .padding()
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
    }

    struct ItemImage: View, Identifiable {
        var id: UUID {
            wrapper.id
        }

        @Environment(\.colorScheme) var colorScheme

        let wrapper: ArchivedItemWrapper

        var body: some View {
            if wrapper.locked {
                Image(systemName: "lock")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 33, height: 33)
                    .foregroundColor(.accentColor)

            } else if let img = wrapper.presentationInfo.image?.swiftUiImage {
                switch wrapper.displayMode {
                case .fit:
                    img
                        .resizable()
                        .accessibilityIgnoresInvertColors()
                        .aspectRatio(contentMode: .fit)
                case .fill:
                    img
                        .resizable()
                        .accessibilityIgnoresInvertColors()
                        .aspectRatio(contentMode: .fill)
                case .circle:
                    img
                        .resizable()
                        .accessibilityIgnoresInvertColors()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(Circle())
                case .center:
                    img
                }
            }
        }
    }

    struct GradientBackgroundStrong: View {
        let fadeColor: Color
        let atTop: Bool

        var body: some View {
            let haze = fadeColor
            let gradient = Gradient(stops: [
                Gradient.Stop(color: haze.opacity(0.7), location: 0.2),
                Gradient.Stop(color: haze.opacity(0.3), location: 0.6),
                Gradient.Stop(color: haze.opacity(0), location: 1.0)
            ])
            LinearGradient(gradient: gradient, startPoint: atTop ? .top : .bottom, endPoint: atTop ? .bottom : .top)
                .padding(atTop ? .bottom : .top, -10)
        }
    }

    struct GradientBackgroundWeak: View {
        let fadeColor: Color
        let atTop: Bool

        var body: some View {
            let haze = fadeColor
            let gradient = Gradient(stops: [
                Gradient.Stop(color: haze.opacity(0.9), location: 0.0),
                Gradient.Stop(color: haze.opacity(0), location: 1.0)
            ])
            LinearGradient(gradient: gradient, startPoint: atTop ? .top : .bottom, endPoint: atTop ? .bottom : .top)
                .padding(atTop ? .bottom : .top, -21)
        }
    }

    struct SelectionTick: View {
        let wrapper: ArchivedItemWrapper

        var body: some View {
            Group {
                if wrapper.flags.contains(.editing) {
                    let selected = wrapper.flags.contains(.selected)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 19)
                        .padding(.leading)
                        .padding(.trailing)
                        .background(.thinMaterial)
                }
            }
        }
    }

    private let wrapper = ArchivedItemWrapper()
    @Environment(\.colorScheme) var colorScheme

    public init() {}

    public func setItem(_ item: ArchivedItem?, for size: CGSize, style: ArchivedItemWrapper.Style) {
        wrapper.configure(with: item, size: size, style: style)
    }

    public func didEndDisplaying() {
        wrapper.clear()
    }

    public func clear() {
        wrapper.clear()
    }

    public var body: some View {
        if wrapper.hasItem {
            itemMode
        }
    }

    public var accessibilityText: String {
        wrapper.accessibilityText
    }

    @ViewBuilder
    private var itemMode: some View {
        #if os(visionOS)
            let shadowColor: Color = wrapper.shouldShowShadow ? .black.opacity(0.3) : .clear
            let cornerRadius = wrapper.cellSize.isCompact ? cellCornerRadius * 0.5 : cellCornerRadius
            let shadowRadius: CGFloat = 6
        #else
            let shadowColor: Color = wrapper.shouldShowShadow ? (colorScheme == .dark ? .black : .gray) : .clear
            let cornerRadius = cellCornerRadius
            let shadowRadius: CGFloat = 2
        #endif
        Group {
            if wrapper.style == .wide {
                WideContentView(wrapper: wrapper)
            } else {
                SquareContentView(wrapper: wrapper)
            }
        }
        .cornerRadius(cornerRadius)
        .shadow(color: shadowColor, radius: shadowRadius)
        .overlay {
            let highlight = wrapper.presentationInfo.highlightColor
            if highlight != .none, let status = wrapper.status, !status.shouldDisplayLoading {
                ZStack {
                    RoundedRectangle(cornerSize: CGSize(width: cellCornerRadius, height: cellCornerRadius), style: .continuous)
                        .stroke(Color(highlight.bgColor), lineWidth: 5)
                    RoundedRectangle(cornerSize: CGSize(width: cellCornerRadius, height: cellCornerRadius), style: .continuous)
                        .inset(by: 2)
                        .stroke(Color.black.opacity(0.2), lineWidth: 2)
                }
            }
        }
        .accessibilityLabel(wrapper.accessibilityText)
    }
}
