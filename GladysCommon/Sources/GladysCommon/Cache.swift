import Foundation

public final class Cache<Key: Hashable, Value> {
    private let store: NSCache<WrappedKey, Entry>
    
    public init() {
        store = NSCache<WrappedKey, Entry>()
    }

    public final class WrappedKey: NSObject {
        public let key: Key

        public init(_ key: Key) {
            self.key = key
        }

        public override var hash: Int {
            key.hashValue
        }

        public override func isEqual(_ object: Any?) -> Bool {
            if let value = object as? WrappedKey {
                return value.key == key
            } else {
                return false
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
