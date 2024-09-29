import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct CreateItemFromText: AppIntent {
        @Parameter(title: "Text")
        var text: String?

        @Parameter(title: "Custom Name")
        var customName: String?

        @Parameter(title: "Note")
        var note: String?

        @Parameter(title: "Labels")
        var labels: [ArchivedItemLabel]?

        static var title: LocalizedStringResource { "Create item from text" }

        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: String = if let text {
                text
            } else {
                try await $text.requestValue()
            }

            let p = NSItemProvider(object: data as NSString)
            let importer = DataImporter(itemProvider: p)
            return try await Model.createItem(provider: importer, title: customName, note: note, labels: labels ?? [], currentFilter: nil)
        }
    }
}
