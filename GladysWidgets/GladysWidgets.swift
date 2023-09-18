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

    private struct ItemCell: View {
        let item: PresentationInfo
        let width: CGFloat
        let height: CGFloat

        @Environment(\.colorScheme) var colorScheme: ColorScheme

        var body: some View {
            ZStack {
                let shadowRadius: CGFloat = 3
                let cornerRadius: CGFloat = 20
                if colorScheme == .light {
                    Rectangle()
                        .foregroundStyle(.background)
                        .cornerRadius(cornerRadius)
                        .shadow(color: .secondary.opacity(0.4), radius: shadowRadius)
                } else {
                    Rectangle()
                        .foregroundStyle(.quaternary)
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
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .font(.caption2).scaleEffect(0.8)
                                .foregroundColor(item.top.isBright ? .black : .white)
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
        let spacing: CGFloat = 12
        let rows = entry.items.bunch(maxSize: Int(colNum))
        let rowNum = CGFloat(rows.count)
        let W = ((entry.displaySize.width - (colNum + 0.5) * spacing) / colNum)
        let H = ((entry.displaySize.height - (rowNum + 0.5) * spacing) / rowNum)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row) { item in
                        Button(intent: itemIntent(for: item.id)) {
                            ItemCell(item: item, width: W, height: H)
                                .allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: entry.displaySize.width, height: entry.displaySize.height)
        .containerBackground(Color(.g_colorPaper), for: .widget)
        .overlay(alignment: .bottomTrailing) {
            Button(intent: itemIntent(for: nil)) {
                Image(systemName: "arrow.down.doc")
                    .font(.title).fontWeight(.light)
                    .padding()
                    .foregroundColor(Color(.g_colorTint))
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            .frame(width: W, height: H)
            .padding(spacing)
        }
    }
}
