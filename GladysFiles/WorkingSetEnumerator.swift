
import FileProvider

final class WorkingSetEnumerator: CommonEnumerator, NSFileProviderEnumerator {

	init() {
		super.init(uuid: NSFileProviderItemIdentifier.workingSet.rawValue)
		log("Enumerator created for working set")
	}

	func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
		observer.finishEnumerating(upTo: nil)
	}

	func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
		log("Listing changes for working set from anchor: \(String(data: syncAnchor.rawValue, encoding: .utf8)!)")
		currentAnchor = syncAnchor
		observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
	}
}
