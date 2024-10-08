import Foundation

public func valueForKeyedArchiverUID(_ item: Any) -> UInt32 {
    var item = item
    return withUnsafeBytes(of: &item) { pointer in
        pointer.load(fromByteOffset: 16, as: UInt32.self)
    }
}

public let isRunningInTestFlightEnvironment: Bool = {
    #if targetEnvironment(simulator)
        return false
    #else
        let sandbox = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        let provision = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
        return sandbox && !provision
    #endif
}()

public func onlyOnMainThread<T: Sendable>(_ block: @Sendable @MainActor () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        try MainActor.assumeIsolated {
            try block()
        }
    } else {
        try DispatchQueue.main.sync {
            try block()
        }
    }
}
