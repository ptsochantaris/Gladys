import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct DeleteItem: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        static var title: LocalizedStringResource { "Delete item" }

        func perform() async throws -> some IntentResult {
            guard let entity,
                  let item = await DropStore.item(uuid: entity.id)
            else {
                throw GladysAppIntentsError.itemNotFound
            }
            await Model.delete(items: [item])
            return .result()
        }
    }
}
