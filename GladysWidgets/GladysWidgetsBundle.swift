import AppIntents
import Foundation
import GladysCommon
import SwiftUI
import WidgetKit

struct CurrentState: TimelineEntry {
    let date: Date
    let displaySize: CGSize
    let items: [PresentationInfo]
}

@main
struct GladysWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GladysWidgets()
    }
}

struct GladysWidgets: Widget {
    let kind = "GladysWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            GladysWidgetsEntryView(entry: entry)
                .containerBackground(Color(.g_colorPaper), for: .widget)
        }
        .configurationDisplayName("Gladgets")
        .description("A grid of your latest items, with optional label or text filtering. Tap an item to copy it.")
        .supportedFamilies([.systemExtraLarge, .systemLarge, .systemMedium, .systemSmall])
    }
}
