import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct CreateItemFromUrl: AppIntent {
        @Parameter(title: "URL")
        var url: URL?

        @Parameter(title: "Custom Name")
        var customName: String?

        @Parameter(title: "Note")
        var note: String?

        @Parameter(title: "Labels")
        var labels: [ArchivedItemLabel]?

        static var title: LocalizedStringResource { "Create item from link" }

        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: URL = if let url {
                url
            } else {
                try await $url.requestValue()
            }

            let p = NSItemProvider(object: data as NSURL)
            let importer = DataImporter(itemProvider: p)
            return try await Model.createItem(provider: importer, title: customName, note: note, labels: labels ?? [], currentFilter: nil)
        }
    }
}
