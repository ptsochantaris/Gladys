import AppIntents
import GladysCommon
import GladysUI

enum GladysAppIntents {
    static func processCreationResult(_ result: PasteResult) async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
        switch result {
        case .noData:
            throw GladysAppIntentsError.noItemsCreated

        case let .success(items):
            guard let item = items.first else {
                throw GladysAppIntentsError.noItemsCreated
            }
            let entity = await ArchivedItemEntity(id: item.uuid, title: item.displayTitleOrUuid)
            let hi = OpenGladys()
            hi.entity = entity
            hi.action = .highlight
            for _ in 0 ..< 20 {
                let ongoing = await DropStore.ingestingItems
                if !ongoing { break }
                try? await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
            }
            return .result(value: entity, opensIntent: hi)
        }
    }
}
