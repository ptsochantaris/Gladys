import Combine
import Foundation

final class PopTimer {
    private let publisher = PassthroughSubject<Void, Never>()
    private var cancel: Cancellable?

    func push() {
        publisher.send()
    }

    func abort() {
        cancel?.cancel()
    }

    var isRunning: Bool {
        cancel != nil
    }

    init(timeInterval: TimeInterval, callback: @escaping () -> Void) {
        let stride = RunLoop.SchedulerTimeType.Stride(timeInterval)
        cancel = publisher.debounce(for: stride, scheduler: RunLoop.main).sink(receiveValue: callback)
    }
}
