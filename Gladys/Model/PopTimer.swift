
import Foundation

final class GladysTimer {

	private let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)

	init(repeats: Bool, interval: TimeInterval, block: @escaping ()->Void) {

		if repeats {
			timer.schedule(deadline: .now() + interval, repeating: interval)
		} else {
			timer.schedule(deadline: .now() + interval)
		}
		timer.setEventHandler(handler: block)
		timer.resume()
	}

	deinit {
		timer.cancel()
	}
}

final class PopTimer {

	private var popTimer: GladysTimer?
	private let timeInterval: TimeInterval
	private let callback: ()->Void

	func push() {
		popTimer = GladysTimer(repeats: false, interval: timeInterval) { [weak self] in
			self?.abort()
			self?.callback()
		}
	}

	func abort() {
		popTimer = nil
	}

	var isRunning: Bool {
		return popTimer != nil
	}

	init(timeInterval: TimeInterval, callback: @escaping ()->Void) {
		self.timeInterval = timeInterval
		self.callback = callback
	}
}
