
import CoreSpotlight

extension ArchivedDropItem {
	func makeIndex(completion: ((Bool)->Void)? = nil) {

		guard let firstItem = typeItems.first else { return }

		let attributes = CSSearchableItemAttributeSet(itemContentType: firstItem.typeIdentifier)
		attributes.title = displayTitle.0
		attributes.contentDescription = accessoryTitle
		attributes.thumbnailURL = firstItem.imagePath
		attributes.providerDataTypeIdentifiers = typeItems.map { $0.typeIdentifier }
		attributes.userCurated = true
		attributes.addedDate = createdAt

		let item = CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: attributes)
		CSSearchableIndex.default().indexSearchableItems([item], completionHandler: { error in
			if let error = error {
				log("Error indexing item \(self.uuid): \(error)")
				completion?(false)
			} else {
				log("Item indexed: \(self.uuid)")
				completion?(true)
			}
		})
	}
}
