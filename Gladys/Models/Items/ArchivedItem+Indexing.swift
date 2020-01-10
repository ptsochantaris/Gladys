
import CoreSpotlight

extension ArchivedItem {

	var searchAttributes: CSSearchableItemAttributeSet {
		let attributes = CSSearchableItemAttributeSet(itemContentType: "build.bru.Gladys.archivedItem")
		if isLocked {
			attributes.title = lockHint
		} else {
			attributes.title = trimmedName
			attributes.textContent = displayText.0
			if note.isEmpty {
				attributes.contentDescription = associatedWebURL?.absoluteString
			} else {
				attributes.contentDescription = note
			}
		}
		if !labels.isEmpty { attributes.keywords = labels }
		attributes.thumbnailURL = imagePath
		attributes.providerDataTypeIdentifiers = components.map { $0.typeIdentifier }
		attributes.userCurated = true
		attributes.addedDate = createdAt
		attributes.contentModificationDate = updatedAt
		return attributes
	}

	var searchableItem: CSSearchableItem {
		return CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: searchAttributes)
	}
}
