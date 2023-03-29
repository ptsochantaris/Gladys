import Foundation
import GladysCommon

final class LoaderBuffer {
    private let queue = DispatchQueue(label: "build.bru.gladys.deserialisation", qos: .utility)
    private var ids = Set<UUID>()
    private var store = ContiguousArray<ArchivedItem?>()

    init(capacity: Int) {
        queue.async {
            self.store = ContiguousArray<ArchivedItem?>(repeating: nil, count: capacity)
            self.ids.reserveCapacity(capacity)
        }
    }

    func set(_ item: ArchivedItem, at index: Int) {
        queue.sync {
            if ids.insert(item.uuid).inserted {
                store[index] = item
            }
        }
    }

    func result() -> ContiguousArray<ArchivedItem> {
        queue.sync {
            ContiguousArray(store.compactMap { $0 })
        }
    }
}
