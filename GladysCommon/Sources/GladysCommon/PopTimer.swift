import Combine
import Foundation

public final class PopTimer {
    private let publisher = PassthroughSubject<Void, Never>()
    private let stride: RunLoop.SchedulerTimeType.Stride
    private let callback: () -> Void
    private var cancel: Cancellable?

    public func push() {
        if cancel == nil {
            cancel = publisher.debounce(for: stride, scheduler: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                cancel = nil
                callback()
            }
        }
        publisher.send()
    }

    public func abort() {
        if let c = cancel {
            c.cancel()
            cancel = nil
        }
    }

    public var isPushed: Bool {
        cancel != nil
    }

    public init(timeInterval: TimeInterval, callback: @escaping () -> Void) {
        self.stride = RunLoop.SchedulerTimeType.Stride(timeInterval)
        self.callback = callback
    }
}
