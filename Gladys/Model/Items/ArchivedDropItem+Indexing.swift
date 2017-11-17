
import CoreSpotlight

extension ArchivedDropItem {
	var searchableItem: CSSearchableItem {

		let attributes = CSSearchableItemAttributeSet(itemContentType: "build.bru.Gladys.archivedItem")
		if let a = accessoryTitle {
			if note.isEmpty {
				attributes.title = a
				attributes.contentDescription = displayTitle.0
			} else {
				if let d = displayTitle.0 {
					attributes.title = "\(a) (\(d))"
				} else {
					attributes.title = a
				}
				attributes.contentDescription = note
			}
		} else {
			attributes.title = displayTitle.0
			if !note.isEmpty {
				attributes.contentDescription = note
			}
		}

		if labels.count > 0 {
			attributes.keywords = labels
		}

		attributes.thumbnailURL = imagePath
		attributes.providerDataTypeIdentifiers = typeItems.map { $0.typeIdentifier }
		attributes.userCurated = true
		attributes.addedDate = createdAt
		attributes.contentModificationDate = updatedAt

		return CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: attributes)
	}

	func reIndex(completion: (()->Void)? = nil) {
		Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: [uuid.uuidString], acknowledgementHandler: completion ?? {})
	}
}

