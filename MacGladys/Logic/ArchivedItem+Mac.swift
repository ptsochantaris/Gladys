import Cocoa

extension ArchivedItem {

    func removeIntents() {}

	func pasteboardItem(forDrag: Bool) -> NSPasteboardWriting? {
		if components.isEmpty { return nil }

		if forDrag, let t = typeItemForFileDrop {
            return GladysFilePromiseProvider.provider(for: t, with: displayTitleOrUuid, extraItems: components, tags: labels)
		} else {
			let pi = NSPasteboardItem()
			components.forEach { $0.add(to: pi) }
			return pi
		}
	}

	var typeItemForFileDrop: Component? {
		return mostRelevantTypeItem ?? components.first(where: { $0.typeConforms(to: kUTTypeContent) || $0.typeConforms(to: kUTTypeItem) }) ?? components.first
	}

	func tryOpen(from viewController: NSViewController) {
		mostRelevantTypeItem?.tryOpen(from: viewController)
	}

	func scanForBlobChanges() -> Bool {
		var someHaveChanged = false
		for component in components { // intended: iterate over all over them, not just until the first one
			if component.scanForBlobChanges() {
				someHaveChanged = true
			}
		}
		return someHaveChanged
	}
    
    var itemProviderForSharing: NSItemProvider {
        let p = NSItemProvider()
        if #available(OSX 10.14, *) {
            p.suggestedName = trimmedSuggestedName
        }
        components.forEach { $0.registerForSharing(with: p) }
        return p
    }
}
