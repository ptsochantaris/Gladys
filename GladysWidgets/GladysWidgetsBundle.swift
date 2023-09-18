import AppIntents
import SwiftUI
import WidgetKit

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
        }
        .configurationDisplayName("Gladgets")
        .description("A grid of your latest items, with optional label or text filtering. Tap an item to copy it.")
        .supportedFamilies([.systemExtraLarge, .systemLarge, .systemMedium, .systemSmall])
    }
}
