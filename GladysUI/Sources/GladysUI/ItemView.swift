import Foundation
import GladysCommon
import SwiftUI

public struct ItemView: View {
    #if os(visionOS)
        static let titleFont = Font.body
    #else
        static let titleFont = Font.caption
    #endif

    struct LoadingItem: View {
        @ObservedObject var wrapper: ArchivedItemWrapper

        var body: some View {
            if wrapper.isFirstImport, let progress = wrapper.loadingProgress?.fractionCompleted {
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
                .accessibilityLabel("Importing item. Activate to cancel.") // TODO: audit
                .accessibilityAction {
                    wrapper.delete()
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .accessibilityLabel("Processing item.") // TODO: audit
            }
        }
    }

    struct ItemImage: View, Identifiable {
        var id: UUID {
            wrapper.id
        }

        @ObservedObject var wrapper: ArchivedItemWrapper
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            if let img = wrapper.presentationInfo.image {
                switch wrapper.displayMode {
                case .fit:
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .fill:
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .circle:
                    img
                        .resizable()
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
                Gradient.Stop(color: haze, location: 0.2),
                Gradient.Stop(color: haze.opacity(0.3), location: 0.8),
                Gradient.Stop(color: haze.opacity(0), location: 1.0)
            ])
            LinearGradient(gradient: gradient, startPoint: atTop ? .top : .bottom, endPoint: atTop ? .bottom : .top)
                .padding(atTop ? .bottom : .top, -26)
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
        @ObservedObject var wrapper: ArchivedItemWrapper

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

    @ObservedObject private var wrapper = ArchivedItemWrapper()
    @Environment(\.colorScheme) var colorScheme

    public init() {}

    public func setItem(_ item: ArchivedItem?, for size: CGSize, style: ArchivedItemWrapper.Style) {
        wrapper.configure(with: item, size: size, style: style)
    }

    public func clear() {
        wrapper.clear()
    }

    public var body: some View {
        if wrapper.hasItem {
            itemMode
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var itemMode: some View {
        #if os(visionOS)
            let cornerRadius = wrapper.compact ? cellCornerRadius * 0.5 : cellCornerRadius
            let shadowRadius: CGFloat = 6
            let shadowColor = wrapper.style.allowsShadows ? Color.black.opacity(0.8) : .clear
        #else
            let cornerRadius = cellCornerRadius
            let shadowRadius: CGFloat = 1.5
            let shadowColor = wrapper.style.allowsShadows ? Color.gray.opacity(0.8) : .clear
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
            if !wrapper.shouldDisplayLoading {
                let highlight = wrapper.presentationInfo.highlightColor
                if highlight != .none {
                    ZStack {
                        RoundedRectangle(cornerSize: CGSize(width: cellCornerRadius, height: cellCornerRadius), style: .continuous)
                            .stroke(Color(highlight.bgColor), lineWidth: 5)
                        RoundedRectangle(cornerSize: CGSize(width: cellCornerRadius, height: cellCornerRadius), style: .continuous)
                            .inset(by: 2)
                            .stroke(Color.black.opacity(0.2), lineWidth: 2)
                    }
                }
            }
        }
        #if !os(visionOS)
        .background {
            if !wrapper.shouldDisplayLoading, !wrapper.locked, wrapper.style.allowsShadows {
                LinearGradient(colors: [
                    wrapper.presentationInfo.top.backgroundColor,
                    wrapper.presentationInfo.bottom.backgroundColor
                ], startPoint: .top, endPoint: .bottom)
                    .cornerRadius(cellCornerRadius)
                    .blur(radius: shadowRadius)
            }
        }
        #endif
    }
}
