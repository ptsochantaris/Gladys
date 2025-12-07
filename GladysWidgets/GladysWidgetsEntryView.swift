import AppIntents
import Foundation
import GladysCommon
import SwiftUI
import WidgetKit

struct GladysWidgetsEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var widgetFamily: WidgetFamily
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    private func itemIntent(for id: UUID) -> GladysAppIntents.OpenGladys {
        let x = GladysAppIntents.OpenGladys()
        x.entity = GladysAppIntents.ArchivedItemEntity(id: id, title: "")
        x.action = .userDefault
        return x
    }

    private struct RowData: Identifiable {
        let id = UUID()
        let items: [PresentationInfo]
    }

    var body: some View {
        let size = entry.displaySize
        let colNum = widgetFamily.colunms
        let rowNum = widgetFamily.rows
        let spacing: CGFloat = 12
        let W = ((size.width - (colNum + 0.5) * spacing) / colNum)
        let H = ((size.height - (rowNum + 0.5) * spacing) / rowNum)
        let extraCount = max(0, Int(colNum * rowNum) - entry.items.count - 1)
        let extras = (0 ..< extraCount).map { _ in
            PresentationInfo()
        }
        let columns = Int((size.width) / (W + spacing))
        let rows = (entry.items + extras)
            .bunch(maxSize: columns)
            .map { RowData(items: $0) }

        Grid(alignment: .center, horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(rows) { row in
                GridRow(alignment: .center) {
                    ForEach(row.items) { presentationInfo in
                        Button(intent: itemIntent(for: presentationInfo.itemId)) {
                            ItemCell(item: presentationInfo, width: W, height: H)
                                .allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }
                    if row.items.count < columns {
                        Button(intent: GladysAppIntents.PasteIntoGladys()) {
                            Image(systemName: "arrow.down.doc")
                                .font(.largeTitle).fontWeight(.light)
                                .foregroundColor(Color(.g_colorTint))
                                .allowsHitTesting(false)
                                .frame(width: W, height: H)
                                .offset(x: -1, y: -1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
