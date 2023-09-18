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
                    if names.contains(entityId) {
                        return LabelOption(id: entityId)
                    }
                    return nil
                }
            }

            @MainActor
            func suggestedEntities() async throws -> [LabelOption] {
                let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))
                filter.rebuildLabels()
                return filter.labelToggles.compactMap {
                    if case .userLabel = $0.function {
                        return LabelOption(id: $0.function.displayText)
                    }
                    return nil
                }
            }
        }

        let id: String
        static var defaultQuery = LabelQuery()
        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Label" }
        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: id) }
    }

    static var title: LocalizedStringResource = "Filter"
    static var description = IntentDescription("Filter using a label or text, leave blank for no fileting")

    @Parameter(title: "Label", default: nil)
    var label: LabelOption?

    @Parameter(title: "Search Term", default: nil)
    var search: String?
}
