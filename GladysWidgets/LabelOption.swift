import AppIntents
import SwiftUI
import WidgetKit

struct LabelOption: AppEntity, Identifiable, Sendable {
    let id: String
    let label: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: label) }
    static let defaultQuery = LabelQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Label" }
    static let clear = LabelOption(id: "", label: "(All labels)")
}
