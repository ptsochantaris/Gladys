import AppIntents
import GladysCommon
import GladysUI
import WidgetKit

struct ConfigIntent: WidgetConfigurationIntent {
    @Parameter(title: "Label", default: nil)
    var label: LabelOption?

    @Parameter(title: "Search Term", default: nil)
    var search: String?

    static let title: LocalizedStringResource = "Filter"
    static let description = IntentDescription("Filter using a label or text, leave blank for no fileting")

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$label
            \.$search
        }
    }
}
