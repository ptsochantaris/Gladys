import AppIntents
import GladysCommon
import GladysUI

/// Pulls in the entity and query types declared in GladysCommon
struct GladysAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [GladysCommonIntentsPackage.self]
    }
}

enum GladysAppIntents {
    /// The item entity lives in GladysCommon so Spotlight indexing and user activities can reference it
    typealias ArchivedItemEntity = GladysCommon.ArchivedItemEntity

    static func processCreationResult(_ result: PasteResult) async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
        switch result {
        case .noData:
            throw GladysAppIntentsError.noItemsCreated

        case let .success(items):
            guard let item = items.first else {
                throw GladysAppIntentsError.noItemsCreated
            }
            let entity = ArchivedItemEntity(item: item)
            let hi = OpenGladys()
            hi.entity = entity
            hi.action = .highlight
            for _ in 0 ..< 20 {
                let ongoing = DropStore.ingestingItems
                if !ongoing { break }
                try? await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
            }
            return .result(value: entity, opensIntent: hi)
        }
    }
}
