//
//  UserDefault.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/05/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Foundation

@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value

    var wrappedValue: Value {
        get {
            PersistedOptions.defaults.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            PersistedOptions.defaults.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
struct OptionalUserDefault<Value> {
    let key: String
    let emptyValue: Value?

    var wrappedValue: Value? {
        get {
            PersistedOptions.defaults.object(forKey: key) as? Value
        }
        set {
            if let newValue = newValue {
                PersistedOptions.defaults.set(newValue, forKey: key)
            } else if let emptyValue = emptyValue {
                PersistedOptions.defaults.set(emptyValue, forKey: key)
            } else {
                PersistedOptions.defaults.removeObject(forKey: key)
            }
        }
    }
}

@propertyWrapper
struct EnumUserDefault<Value: RawRepresentable> {
    let key: String
    let defaultValue: Value

    var wrappedValue: Value {
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
