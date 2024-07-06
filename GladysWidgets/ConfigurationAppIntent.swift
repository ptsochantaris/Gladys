import AppIntents
import GladysCommon
import GladysUI
import WidgetKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    struct LabelOption: AppEntity, Identifiable {
        struct LabelQuery: EntityStringQuery {
            func entities(matching string: String) async throws -> [LabelOption] {
                let all = try await suggestedEntities()
                return all.filter { $0.id.localizedCaseInsensitiveContains(string) }
            }

            @MainActor
            func entities(for identifiers: [ID]) async throws -> [LabelOption] {
                let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))
                filter.rebuildLabels()
                let names = Set(filter.labelToggles.map(\.function.displayText))
                return identifiers.compactMap { entityId in
                    if entityId == "" {
                        return LabelOption.clear
                    }
                    if names.contains(entityId) {
                        return LabelOption(id: entityId, label: entityId)
                    }
                    return nil
                }
            }

            @MainActor
            func suggestedEntities() async throws -> [LabelOption] {
                let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))
                filter.rebuildLabels()
                return [LabelOption.clear] + filter.labelToggles.compactMap {
                    if case .userLabel = $0.function {
                        let labelText = $0.function.displayText
                        return LabelOption(id: labelText, label: labelText)
                    }
                    return nil
                }
            }
        }

        static let defaultQuery = LabelQuery()
        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Label" }
        static let clear = LabelOption(id: "", label: "(All labels)")

        let id: String
        let label: String
        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: label) }
    }

    static let title: LocalizedStringResource = "Filter"
    static let description = IntentDescription("Filter using a label or text, leave blank for no fileting")

    @Parameter(title: "Label", default: nil)
    var label: LabelOption?

    @Parameter(title: "Search Term", default: nil)
    var search: String?
}
