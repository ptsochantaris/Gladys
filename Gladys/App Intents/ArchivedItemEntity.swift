import AppIntents
import Foundation

extension GladysAppIntents {
    struct ArchivedItemEntity: AppEntity, Identifiable {
        let id: UUID
        let title: String

        static let defaultQuery = ArchivedItemQuery()

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Item" }

        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: title) }
    }
}
