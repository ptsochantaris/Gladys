
import Foundation

extension ArchivedDropItem: LoadCompletionDelegate {
	
	func loadCompleted(sender: AnyObject, success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			isLoading = false
			delegate?.loadCompleted(sender: self, success: allLoadedWell)
		}
	}

	func loadingProgress(sender: AnyObject) { }

	func cancelIngest() {
		typeItems.forEach { $0.cancelIngest() }
	}

	func reIngest(delegate: LoadCompletionDelegate) {
		self.delegate = delegate
		typeItems.forEach { $0.reIngest(delegate: self) }
	}
}
