import Foundation

public final class LoaderBuffer {
    private let queue = DispatchQueue(label: "build.bru.gladys.deserialisation")

    private var store = ContiguousArray<ArchivedItem?>()

    public init(capacity: Int) {
        queue.async {
            self.store = ContiguousArray<ArchivedItem?>(repeating: nil, count: capacity)
        }
    }

    public func set(_ item: ArchivedItem, at index: Int) {
        queue.async {
            self.store[index] = item
        }
    }

    public func result() -> ContiguousArray<ArchivedItem> {
        queue.sync {
            ContiguousArray(store.compactMap { $0 })
        }
    }
}
