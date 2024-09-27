import AppIntents
import Foundation
import GladysCommon
import SwiftUI
import WidgetKit

struct GladysWidgetsEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var widgetFamily: WidgetFamily
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

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
        let colNum = widgetFamily.colunms
        let rowNum = widgetFamily.rows
        let spacing: CGFloat = 12
        let W = ((entry.displaySize.width - (colNum + 0.5) * spacing) / colNum)
        let H = ((entry.displaySize.height - (rowNum + 0.5) * spacing) / rowNum)
        let extraCount = max(0, Int(colNum * rowNum) - entry.items.count - 1)
        let extras = (0 ..< extraCount).map { _ in
            PresentationInfo()
        }
        Grid(alignment: .center, horizontalSpacing: spacing, verticalSpacing: spacing) {
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
