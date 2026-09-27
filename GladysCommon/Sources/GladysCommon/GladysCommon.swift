import Foundation
import StoreKit

public nonisolated func valueForKeyedArchiverUID(_ item: Any) -> UInt32 {
    var item = item
    return withUnsafeBytes(of: &item) { pointer in
        pointer.load(fromByteOffset: 16, as: UInt32.self)
    }
}

public nonisolated func isRunningInTestFlightEnvironment() async -> Bool {
    #if targetEnvironment(simulator)
        return false
    #else
        // Development builds carry a provisioning profile; TestFlight builds don't, but still run in the sandbox
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            return false
        }
        guard let appTransaction = try? await AppTransaction.shared.payloadValue else {
            return false
        }
        return appTransaction.environment == .sandbox
    #endif
}

public nonisolated func onlyOnMainThread<T: Sendable>(_ block: @Sendable @MainActor () throws -> T) rethrows -> T {
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

public nonisolated func onlyOnMainThread<T: Sendable>(_ block: @Sendable @MainActor () -> T) -> T {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            block()
        }
    } else {
        DispatchQueue.main.sync {
            block()
        }
    }
}
