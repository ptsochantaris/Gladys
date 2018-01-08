import Foundation
import FileProvider

extension Model {

	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	static func prepareToSave() {}
	static func saveComplete() {}
	static func startupComplete() {}

	static func signalRootChange() {
		NSFileProviderManager.default.signalEnumerator(for: .rootContainer) { error in
			if let e = error {
				log("Error signalling: \(e.finalDescription)")
			}
		}
	}

	static func signalWorkingSetChange() {
		NSFileProviderManager.default.signalEnumerator(for: .workingSet) { error in
			if let e = error {
				log("Error signalling: \(e.finalDescription)")
			}
		}
	}

	static func reloadCompleted() {
		Model.signalRootChange()
		Model.signalWorkingSetChange()
	}

	static var visibleDrops: [ArchivedDropItem] {
		if Model.legacyMode {
			return []
		}
		return drops.filter { !$0.needsDeletion }
	}
}
