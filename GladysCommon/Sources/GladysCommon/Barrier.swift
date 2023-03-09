import Combine
import Foundation

public final actor Barrier {
    public enum State {
        case locked, unlocked

        var immediateResult: Bool? {
            switch self {
            case .locked:
                return nil
            case .unlocked:
                return true
            }
        }
    }

    public init() {}

    private let publisher = CurrentValueSubject<State, Never>(.unlocked)

    public var state: State {
        publisher.value
    }

    public func lock() {
        if publisher.value == .unlocked {
            publisher.send(.locked)
        }
    }

    public func unlock() {
        if publisher.value == .locked {
            publisher.send(.unlocked)
        }
    }

    @discardableResult
    public func wait() async -> Bool {
        if let result = publisher.value.immediateResult {
            return result
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            _ = publisher
                .handleEvents(receiveCancel: {
                    continuation.resume(returning: false)
                })
                .sink { value in
                    switch value {
                    case .locked:
                        break // shouldn't happen
                    case .unlocked:
                        continuation.resume(returning: true)
                    }
                }
        }
    }

    @discardableResult
    public func wait(seconds: Int) async -> Bool {
        if let result = publisher.value.immediateResult {
            return result
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.wait()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(seconds))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
