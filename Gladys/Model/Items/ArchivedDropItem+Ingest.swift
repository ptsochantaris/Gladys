
import Foundation

extension ArchivedDropItem: LoadCompletionDelegate {
	
	func loadCompleted(sender: AnyObject, success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			loadingProgress = nil
			delegate?.loadCompleted(sender: self, success: allLoadedWell)
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

			for typeIdentifier in identifiers {
				loadCount += 1
				let i = ArchivedDropItemType(typeIdentifier: typeIdentifier, parentUuid: uuid, delegate: self)
				let p = i.startIngest(provider: provider, delegate: self, encodeAnyUIImage: shouldCreateEncodedImage)
				progressChildren.append(p)
				typeItems.append(i)
			}
		}
		let p = Progress(totalUnitCount: Int64(progressChildren.count * 100))
		for c in progressChildren {
			p.addChild(c, withPendingUnitCount: 100)
		}
		return p
	}
}
