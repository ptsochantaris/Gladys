import Foundation
import GladysCommon

final class LoaderBuffer {
    private let queue = DispatchSemaphore(value: 1)
    private var ids = Set<UUID>()
    private let store: UnsafeMutableBufferPointer<ArchivedItem?>

    init(capacity: Int) {
        store = .allocate(capacity: capacity)
        store.initialize(repeating: nil)
        ids.reserveCapacity(capacity)
    }

    func set(_ item: ArchivedItem, at index: Int, uuid: UUID) {
        queue.wait()
        let inserted = ids.insert(uuid).inserted
        queue.signal()
        if inserted {
            store[index] = item
        }
    }

    func result() -> some Sequence<ArchivedItem> {
        store.compactMap { $0 }
    }
    
    deinit {
        store.deallocate()
    }
}
