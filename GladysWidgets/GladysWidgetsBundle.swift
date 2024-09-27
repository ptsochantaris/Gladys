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
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GladysWidgets", intent: ConfigIntent.self, provider: Provider()) {
            GladysWidgetsEntryView(entry: $0)
                .containerBackground(Color(.g_colorPaper), for: .widget)
        }
        .configurationDisplayName("Gladgets")
        .description("A grid of your latest items, with optional label or text filtering. Tap an item to copy it.")
        .supportedFamilies([.systemExtraLarge, .systemLarge, .systemMedium, .systemSmall])
    }
}
