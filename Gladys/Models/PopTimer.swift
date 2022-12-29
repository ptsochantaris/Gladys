import Foundation

final class GladysTimer {
    private let timer: DispatchSourceTimer

    init(interval: TimeInterval, block: @escaping () -> Void) {
        timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler(handler: block)
        timer.resume()
    }

    deinit {
        timer.cancel()
    }
}

@MainActor
final class PopTimer {
    private var popTimer: GladysTimer?
    private let timeInterval: TimeInterval
    private let callback: () -> Void

    func push() {
        popTimer = GladysTimer(interval: timeInterval) { [weak self] in
            guard let self else { return }
            self.abort()
            self.callback()
        }
    }

    func abort() {
        popTimer = nil
    }

    var isRunning: Bool {
        popTimer != nil
    }

    init(timeInterval: TimeInterval, callback: @escaping () -> Void) {
        self.timeInterval = timeInterval
        self.callback = callback
    }
}
