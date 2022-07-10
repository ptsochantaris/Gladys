import Foundation

typealias BarrierTask = Task<Void, Never>

final actor TaskLock {
    private var task: BarrierTask?

    init(preLocked: Bool = false) {
        if preLocked {
            task = TaskLock.startBarrierTask()
        }
    }

    static func startBarrierTask() -> BarrierTask {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * NSEC_PER_SEC)
            }
        }
    }

    var isLocked: Bool {
        task != nil
    }

    func lock() {
        if task == nil {
            task = TaskLock.startBarrierTask()
        }
    }

    func unlock() {
        task?.cancel()
        task = nil
    }

    func wait() async {
        await task?.value
    }

    func wait(seconds: Int) async -> Bool {
        var loops = 0
        while isLocked {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            loops += 1
        }
        return loops <= (seconds * 10)
    }
}
