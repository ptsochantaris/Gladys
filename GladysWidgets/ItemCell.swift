import Foundation
import GladysCommon
import SwiftUI

struct ItemCell: View {
    let item: PresentationInfo
    let width: CGFloat
    let height: CGFloat

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        ZStack {
            let shadowRadius: CGFloat = 3
            let cornerRadius: CGFloat = 20
            let bgOpacity = item.isPlaceholder ? 0.6 : 1
            if colorScheme == .light {
                Rectangle()
                    .foregroundStyle(.background.opacity(bgOpacity))
                    .cornerRadius(cornerRadius)
                    .shadow(color: .secondary.opacity(0.4), radius: shadowRadius)
            } else {
                Rectangle()
                    .foregroundStyle(.quaternary.opacity(bgOpacity))
                    .cornerRadius(cornerRadius)
                    .shadow(color: .black, radius: shadowRadius)
            }

            if item.isPlaceholder {
                // nothing

            } else if item.hasFullImage, let img = item.image?.swiftUiImage {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(cornerRadius)

            } else {
                VStack(spacing: 0) {
                    if let img = item.image?.swiftUiImage {
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36)
                    }

                    if let title = item.top.content.rawText ?? item.bottom.content.rawText {
                        Text(title)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .font(.caption2).scaleEffect(0.8)
                            .foregroundColor(item.hasFullImage ? (item.top.isBright ? .black : .white) : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .offset(y: 2)
            }
        }
        .frame(width: width, height: height)
    }
}
