
import Foundation

struct ImportOverrides {
	let title: String?
	let note: String?
	let labels: [String]?
}

extension ArchivedDropItem: LoadCompletionDelegate {
	
	func loadCompleted(sender: AnyObject) {
		loadCount = loadCount - 1
		if loadCount == 0 {
			loadingProgress = nil
			delegate?.loadCompleted(sender: self)
			delegate = nil
		}
	}

	func cancelIngest() {
		typeItems.forEach { $0.cancelIngest() }
	}

	func reIngest(delegate: LoadCompletionDelegate) {
		loadCount = typeItems.count
		self.delegate = delegate
		let p = Progress(totalUnitCount: Int64(typeItems.count * 100))
		loadingProgress = p
		typeItems.forEach {
			let cp = $0.reIngest(delegate: self)
			p.addChild(cp, withPendingUnitCount: 100)
		}
	}

	static func sanitised(_ idenitfiers: [String]) -> [String] {
		let blockedSuffixes = [".useractivity", ".internalMessageTransfer", "itemprovider", ".rtfd"]
		return idenitfiers.filter { typeIdentifier in
			!blockedSuffixes.contains(where: { typeIdentifier.hasSuffix($0) })
		}
	}

	func startIngest(providers: [NSItemProvider], delegate: LoadCompletionDelegate?, limitToType: String?) -> Progress {
		self.delegate = delegate
		var progressChildren = [Progress]()

		for provider in providers {

			var identifiers = ArchivedDropItem.sanitised(provider.registeredTypeIdentifiers)
			let shouldCreateEncodedImage = identifiers.contains("public.image") && !identifiers.contains { $0.hasPrefix("public.image.") }

			if let limit = limitToType {
				identifiers = [limit]
			}

			func addTypeItem(type: String, encodeUIImage: Bool) {
				loadCount += 1
				let i = ArchivedDropItemType(typeIdentifier: type, parentUuid: uuid, delegate: self)
				let p = i.startIngest(provider: provider, delegate: self, encodeAnyUIImage: encodeUIImage)
				progressChildren.append(p)
				typeItems.append(i)
			}

			for typeIdentifier in identifiers {
				if typeIdentifier == "public.image" && shouldCreateEncodedImage {
					addTypeItem(type: "public.image", encodeUIImage: true)
				}
				addTypeItem(type: typeIdentifier, encodeUIImage: false)
			}
		}
		let p = Progress(totalUnitCount: Int64(progressChildren.count * 100))
		for c in progressChildren {
			p.addChild(c, withPendingUnitCount: 100)
		}
		return p
	}
}
