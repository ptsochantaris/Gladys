import AppIntents
import Foundation

extension GladysAppIntents {
    struct ArchivedItemLabel: AppEntity, Identifiable {
        let id: String

        static let defaultQuery = ArchivedItemLabelQuery()

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Label" }

        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: id) }
    }
}
