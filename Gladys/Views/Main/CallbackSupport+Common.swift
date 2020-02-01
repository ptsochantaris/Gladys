import Foundation
import CallbackURLKit

extension CallbackSupport {
	static func createOverrides(from parameters: [String: String]) -> ImportOverrides {
		let title = parameters["title"]
		let labels = parameters["labels"]
		let note = parameters["note"]
		let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		return ImportOverrides(title: title, note: note, labels: labelsList)
	}

	@discardableResult
	static func handlePossibleCallbackURL(url: URL) -> Bool {
		return Manager.shared.handleOpen(url: url)
	}
}
