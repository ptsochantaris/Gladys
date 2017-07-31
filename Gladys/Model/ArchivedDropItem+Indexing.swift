
import CoreSpotlight

extension ArchivedDropItem {
	func makeIndex(completion: ((Bool)->Void)? = nil) {

		let attributes = CSSearchableItemAttributeSet(itemContentType: "build.bru.Gladys.archivedItem")
		if let a = accessoryTitle {
			attributes.title = a
			attributes.contentDescription = displayTitle.0
		} else {
			attributes.title = displayTitle.0
		}
		attributes.thumbnailURL = imagePath
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
