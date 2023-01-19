import Foundation

public typealias BarrierTask = Task<Void, Never>

public final actor TaskLock {
    private var task: BarrierTask?

    public init(preLocked: Bool = false) {
        if preLocked {
            task = TaskLock.startBarrierTask()
        }
    }

    public static func startBarrierTask() -> BarrierTask {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * NSEC_PER_SEC)
            }
        }
    }

    public var isLocked: Bool {
        task != nil
    }

    public func lock() {
        if task == nil {
            task = TaskLock.startBarrierTask()
        }
    }

    public func unlock() {
        task?.cancel()
        task = nil
    }

    public func wait() async {
        await task?.value
    }

    public func wait(seconds: Int) async -> Bool {
        var loops = 0
        while isLocked {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            loops += 1
        }
        return loops <= (seconds * 10)
    }
}
