
import Foundation

class LoadCompletionCounter: LoadCompletionDelegate {
	weak var delegate: LoadCompletionDelegate?
	var isLoading = true

	private var loadCount: Int
	private var allLoadedWell = true
 	func loadCompleted(success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			isLoading = false
			delegate?.loadCompleted(success: allLoadedWell)
		}
	}
	init(loadCount: Int, delegate: LoadCompletionDelegate?) {
		self.delegate = delegate
		self.loadCount = loadCount
	}
}
