import AppIntents
import GladysCommon
import Lista
import SwiftUI
import WidgetKit

struct GladysWidgetsEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var widgetFamily: WidgetFamily
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    private func colunms(in widgetFamily: WidgetFamily) -> Int {
        switch widgetFamily {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 2
        case .systemMedium: 4
        case .systemLarge: 4
        case .systemExtraLarge: 8
        @unknown default: 1
        }
    }

    private func rows(in widgetFamily: WidgetFamily) -> Int {
        switch widgetFamily {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 2
        case .systemMedium: 2
        case .systemLarge: 4
        case .systemExtraLarge: 4
        @unknown default: 1
        }
    }

    private struct ItemCell: View {
        let item: PresentationInfo
        let width: CGFloat
        let height: CGFloat

        @Environment(\.colorScheme) var colorScheme: ColorScheme

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

                } else if item.hasFullImage, let img = item.image {
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                        .cornerRadius(cornerRadius)

                } else {
                    VStack(spacing: 0) {
                        if let img = item.image {
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

    private func itemIntent(for id: UUID?) -> any AppIntent {
        if let id {
            let x = GladysAppIntents.OpenGladys()
            x.entity = GladysAppIntents.ArchivedItemEntity(id: id, title: "")
            x.action = .userDefault
            return x
        } else {
            return GladysAppIntents.PasteIntoGladys()
        }
    }

    var body: some View {
        let colNum = CGFloat(colunms(in: widgetFamily))
        let rowNum = CGFloat(rows(in: widgetFamily))
        let spacing: CGFloat = 12
        let W = ((entry.displaySize.width - (colNum + 0.5) * spacing) / colNum)
        let H = ((entry.displaySize.height - (rowNum + 0.5) * spacing) / rowNum)
        let colDefs = [GridItem](repeating: GridItem(.flexible(minimum: min(W, H), maximum: max(W, H)), spacing: spacing), count: Int(colNum))
        let extras = (0 ..< max(0, Int(colNum * rowNum) - entry.items.count - 1)).map { _ in
            PresentationInfo()
        }
        LazyVGrid(columns: colDefs, spacing: spacing) {
            ForEach(entry.items + extras) { item in
                Button(intent: itemIntent(for: item.id)) {
                    ItemCell(item: item, width: W, height: H)
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            }
            Button(intent: itemIntent(for: nil)) {
                Image(systemName: "arrow.down.doc")
                    .font(.largeTitle).fontWeight(.light)
                    .foregroundColor(Color(.g_colorTint))
                    .allowsHitTesting(false)
                    .frame(width: W, height: H)
                    .offset(x: -1, y: -1)
            }
            .buttonStyle(.plain)
        }
        .frame(width: entry.displaySize.width, height: entry.displaySize.height)
    }
}
