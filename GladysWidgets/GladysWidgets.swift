import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct GladysWidgets: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GladysWidgets", intent: ConfigIntent.self, provider: Provider()) {
            GladysWidgetsEntryView(entry: $0)
                .containerBackground(Color(.g_colorPaper), for: .widget)
        }
        .configurationDisplayName("Gladgets")
        .description("A grid of your latest items, with optional label or text filtering. Select an item to view it in the app.")
        .supportedFamilies([.systemExtraLarge, .systemLarge, .systemMedium, .systemSmall])
    }
}
