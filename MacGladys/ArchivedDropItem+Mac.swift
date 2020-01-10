import Cocoa

extension ArchivedDropItem {

    func removeIntents() {}

	func pasteboardItem(forDrag: Bool) -> NSPasteboardWriting? {
		if typeItems.isEmpty { return nil }

		if forDrag, let t = typeItemForFileDrop {
            return GladysFilePromiseProvider.provider(for: t, with: displayTitleOrUuid, extraItems: typeItems, tags: labels)
		} else {
			let pi = NSPasteboardItem()
			typeItems.forEach { $0.add(to: pi) }
			return pi
		}
	}

	var typeItemForFileDrop: ArchivedDropItemType? {
		return mostRelevantTypeItem ?? typeItems.first(where: { $0.typeConforms(to: kUTTypeContent) || $0.typeConforms(to: kUTTypeItem) }) ?? typeItems.first
	}

	func tryOpen(from viewController: NSViewController) {
		mostRelevantTypeItem?.tryOpen(from: viewController)
	}

	func scanForBlobChanges() -> Bool {
		var someHaveChanged = false
		for component in typeItems { // intended: iterate over all over them, not just until the first one
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
        typeItems.forEach { $0.registerForSharing(with: p) }
        return p
    }
}
