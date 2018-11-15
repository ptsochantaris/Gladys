
import CoreSpotlight

extension ArchivedDropItem {

	var searchAttributes: CSSearchableItemAttributeSet {
		let attributes = CSSearchableItemAttributeSet(itemContentType: "build.bru.Gladys.archivedItem")
		if isLocked {
			attributes.title = lockHint
		} else {
			attributes.title = displayText.0
			if note.isEmpty {
				attributes.contentDescription = associatedWebURL?.absoluteString
			} else {
				attributes.contentDescription = note
			}
		}
		if labels.count > 0 { attributes.keywords = labels }
		attributes.thumbnailURL = imagePath
		attributes.providerDataTypeIdentifiers = typeItems.map { $0.typeIdentifier }
		attributes.userCurated = true
		attributes.addedDate = createdAt
		attributes.contentModificationDate = updatedAt
		return attributes
	}

	var searchableItem: CSSearchableItem {
		return CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: searchAttributes)
	}
}
