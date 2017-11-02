
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

	func startIngest(providers: [NSItemProvider], delegate: LoadCompletionDelegate?) -> Progress {
		self.delegate = delegate
		var progressChildren = [Progress]()

		let blockedSuffixes = [".useractivity", ".internalMessageTransfer", "itemprovider", ".rtfd"]

		for provider in providers {

			let identifiers = provider.registeredTypeIdentifiers
			var shouldCreateEncodedImage = false
			if identifiers.contains("public.image") {
				if !identifiers.contains(where: { $0.hasPrefix("public.image.") }) {
					shouldCreateEncodedImage = true
				}
			}

			for typeIdentifier in identifiers {
				if !blockedSuffixes.contains(where: { typeIdentifier.hasSuffix($0) } ) {
					loadCount += 1
					let i = ArchivedDropItemType(typeIdentifier: typeIdentifier, parentUuid: uuid, delegate: self)
					let p = i.startIngest(provider: provider, delegate: self, encodeAnyUIImage: shouldCreateEncodedImage)
					progressChildren.append(p)
					typeItems.append(i)
				}
			}
		}
		let p = Progress(totalUnitCount: Int64(progressChildren.count * 100))
		for c in progressChildren {
			p.addChild(c, withPendingUnitCount: 100)
		}
		return p
	}
}
