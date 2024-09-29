import AppIntents
import GladysCommon
import GladysUI
import WidgetKit

struct ConfigIntent: WidgetConfigurationIntent {
    @Parameter(title: "Label", default: nil)
    var label: LabelOption?

    @Parameter(title: "Search Term", default: nil)
    var search: String?

    static let title: LocalizedStringResource = "Gladgets"
    static let description = IntentDescription("A grid of your latest items, with optional label or text filtering. Select an item to view it in the app.")

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$label
            \.$search
        }
    }
}
