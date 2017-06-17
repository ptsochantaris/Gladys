
import UIKit

final class ArchivedDropItem: LoadCompletionCounter {

	private let uuid = UUID()
	private let suggestedName: String?
	private var typeItems: [ArchivedDropItemType]!

	var displayIcon: (UIImage?, UIViewContentMode) {
		var priority = -1
		var image: UIImage?
		var contentMode = UIViewContentMode.center
		for i in typeItems {
			let (newImage, newPriority, newContentMode) = i.displayIcon
			if let newImage = newImage, newPriority > priority {
				image = newImage
				priority = newPriority
				contentMode = newContentMode
			}
		}
		return (image, contentMode)
	}

	var displayTitle: String? {
		if let suggestedName = suggestedName {
			return suggestedName
		}
		var title: String?
		var priority = -1
		for i in typeItems {
			let (newTitle, newPriority) = i.displayTitle
			if let newTitle = newTitle, newPriority > priority {
				title = newTitle
				priority = newPriority
			}
		}
		return title
	}

	var myURL: URL {
		let f = FileManager.default
		let docs = f.urls(for: .documentDirectory, in: .userDomainMask).first!
		return docs.appendingPathComponent(uuid.uuidString)
	}

	init(provider: NSItemProvider, delegate: LoadCompletionDelegate) {
		suggestedName = provider.suggestedName
		super.init(loadCount: provider.registeredTypeIdentifiers.count, delegate: delegate)
		typeItems = provider.registeredTypeIdentifiers.map { ArchivedDropItemType(provider: provider, typeIdentifier: $0, parentUrl: myURL, delegate: self) }
	}

	var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = suggestedName
		for item in typeItems {
			p.registerItem(forTypeIdentifier: item.typeIdentifier, loadHandler: item.loadHandler)
		}
		return p
	}
}
