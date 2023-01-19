import Foundation

@propertyWrapper
public struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    
    public init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Value {
        get {
            PersistedOptions.defaults.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            PersistedOptions.defaults.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
public struct OptionalUserDefault<Value> {
    let key: String
    let emptyValue: Value?

    public init(key: String, emptyValue: Value?) {
        self.key = key
        self.emptyValue = emptyValue
    }

    public var wrappedValue: Value? {
        get {
            PersistedOptions.defaults.object(forKey: key) as? Value
        }
        set {
            if let newValue {
                PersistedOptions.defaults.set(newValue, forKey: key)
            } else if let emptyValue {
                PersistedOptions.defaults.set(emptyValue, forKey: key)
            } else {
                PersistedOptions.defaults.removeObject(forKey: key)
            }
        }
    }
}

@propertyWrapper
public struct EnumUserDefault<Value: RawRepresentable> {
    let key: String
    let defaultValue: Value
    
    public init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Value {
        get {
            if let o = PersistedOptions.defaults.object(forKey: key) as? Value.RawValue, let v = Value(rawValue: o) {
                return v
            }
            return defaultValue
        }
        set {
            PersistedOptions.defaults.set(newValue.rawValue, forKey: key)
        }
    }
}
