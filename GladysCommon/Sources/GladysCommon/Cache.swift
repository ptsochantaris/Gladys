import Foundation

public final class Cache<Key: Hashable, Value>: Sendable {
    private nonisolated(unsafe) let store: NSCache<WrappedKey, Entry>

    public init() {
        store = NSCache<WrappedKey, Entry>()
    }

    public final class WrappedKey: NSObject {
        public let key: Key

        public init(_ key: Key) {
            self.key = key
        }

        override public var hash: Int {
            key.hashValue
        }

        override public func isEqual(_ object: Any?) -> Bool {
            if let value = object as? WrappedKey {
                value.key == key
            } else {
                false
            }
        }
    }

    public final class Entry {
        let value: Value

        public init(value: Value) {
            self.value = value
        }
    }

    public func reset() {
        store.removeAllObjects()
    }

    public subscript(key: Key) -> Value? {
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
