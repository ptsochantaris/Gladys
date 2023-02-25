import Foundation

public final class LoaderBuffer {
    private let queue = DispatchQueue(label: "build.bru.gladys.deserialisation", qos: .background)
    private var ids = Set<UUID>()
    private var store = ContiguousArray<ArchivedItem?>()

    public init(capacity: Int) {
        queue.async {
            self.store = ContiguousArray<ArchivedItem?>(repeating: nil, count: capacity)
            self.ids.reserveCapacity(capacity)
        }
    }

    public func set(_ item: ArchivedItem, at index: Int) {
        queue.async {
            if self.ids.insert(item.uuid).inserted {
                self.store[index] = item
            }
        }
    }

    public func result() -> ContiguousArray<ArchivedItem> {
        queue.sync {
            ContiguousArray(store.compactMap { $0 })
        }
    }
}
