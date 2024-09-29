import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct CreateItemFromFile: AppIntent {
        @Parameter(title: "File")
        var file: IntentFile?

        @Parameter(title: "Custom Name")
        var customName: String?

        @Parameter(title: "Note")
        var note: String?

        @Parameter(title: "Labels")
        var labels: [ArchivedItemLabel]?

        static var title: LocalizedStringResource { "Create item from file" }

        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: IntentFile = if let file {
                file
            } else {
                try await $file.requestValue()
            }

            let importer = DataImporter(type: (data.type ?? .data).identifier, data: data.data, suggestedName: data.filename)
            return try await Model.createItem(provider: importer, title: customName, note: note, labels: labels ?? [], currentFilter: nil)
        }
    }
}
