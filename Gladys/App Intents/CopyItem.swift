import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct CopyItem: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        static var title: LocalizedStringResource { "Copy item to clipboard" }

        func perform() async throws -> some IntentResult {
            guard let entity,
                  let item = await DropStore.item(uuid: entity.id)
            else {
                throw GladysAppIntentsError.itemNotFound
            }
            await item.copyToPasteboard()
            return .result()
        }
    }
}
