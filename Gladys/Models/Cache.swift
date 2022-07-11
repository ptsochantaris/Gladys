import Foundation

final class Cache<Key: Hashable, Value> {
    private let store = NSCache<WrappedKey, Entry>()

    final class WrappedKey: NSObject {
        let key: Key

        init(_ key: Key) {
            self.key = key
        }

        override var hash: Int {
            key.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            if let value = object as? WrappedKey {
                return value.key == key
            } else {
                return false
            }
        }
    }

    final class Entry {
        let value: Value

        init(value: Value) {
            self.value = value
        }
    }

    func reset() {
        store.removeAllObjects()
    }

    subscript(key: Key) -> Value? {
        get {
            store.object(forKey: WrappedKey(key))?.value
        }
        set {
            if let value = newValue {
                store.setObject(Entry(value: value), forKey: WrappedKey(key))
            } else {
                store.removeObject(forKey: WrappedKey(key))
            }
        }
    }
}
