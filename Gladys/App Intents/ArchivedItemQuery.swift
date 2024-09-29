import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct ArchivedItemQuery: EntityStringQuery {
        func entities(matching string: String) async throws -> [ArchivedItemEntity] {
            await MainActor.run {
                let filter = Filter()
                filter.text = string
                return filter.filteredDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
            }
        }

        func entities(for identifiers: [ArchivedItemEntity.ID]) async throws -> [ArchivedItemEntity] {
            await MainActor.run {
                identifiers.compactMap { DropStore.item(uuid: $0) }.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
            }
        }

        func suggestedEntities() async throws -> [ArchivedItemEntity] {
            await MainActor.run {
                DropStore.allDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
            }
        }
    }
}
