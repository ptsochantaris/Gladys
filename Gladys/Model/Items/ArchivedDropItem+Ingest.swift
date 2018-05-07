
import Foundation

struct ImportOverrides {
	let title: String?
	let note: String?
	let labels: [String]?
}

extension ArchivedDropItem: LoadCompletionDelegate {

	static func sanitised(_ idenitfiers: [String]) -> [String] {
		let blockedSuffixes = [".useractivity", ".internalMessageTransfer", "itemprovider", ".rtfd"]
		return idenitfiers.filter { typeIdentifier in
			!blockedSuffixes.contains(where: { typeIdentifier.hasSuffix($0) })
		}
	}

	func loadCompleted(sender: AnyObject) {
		loadCount = loadCount - 1
		if loadCount <= 0 {
			loadingProgress = nil
			if let d = delegate {
				delegate = nil
				d.loadCompleted(sender: self)
			}
		}
	}

	func cancelIngest() {
		typeItems.forEach { $0.cancelIngest() }
	}

	func reIngest(delegate: LoadCompletionDelegate) {
		self.delegate = delegate
		loadCount = typeItems.count
		let wasExplicitlyUnlocked = lockPassword != nil && !needsUnlock
		needsUnlock = lockPassword != nil && !wasExplicitlyUnlocked
		let p = Progress(totalUnitCount: Int64(loadCount * 100))
		loadingProgress = p
		if typeItems.count == 0 { // can happen for example when all components are removed
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				self.loadCompleted(sender: self)
			}
		} else {
			if typeItems.count > 1 && typeItems.filter({ $0.order != 0 }).count > 0 { // some type items have an order set, enforce it
				typeItems.sort { $0.order < $1.order }
			}
			typeItems.forEach {
				let cp = $0.reIngest(delegate: self)
				p.addChild(cp, withPendingUnitCount: 100)
			}
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

			func addTypeItem(type: String, encodeUIImage: Bool, order: Int) {
				loadCount += 1
				let i = ArchivedDropItemType(typeIdentifier: type, parentUuid: uuid, delegate: self, order: order)
				let p = i.startIngest(provider: provider, delegate: self, encodeAnyUIImage: encodeUIImage)
				progressChildren.append(p)
				typeItems.append(i)
			}

			var order = 0
			for typeIdentifier in identifiers {
				#if os(OSX) // TODO: perhaps do this on iOS too?
				let cfid = typeIdentifier as CFString
				if !(UTTypeConformsTo(cfid, kUTTypeItem) || UTTypeConformsTo(cfid, kUTTypeContent)) { continue }
				#endif
				if typeIdentifier == "public.image" && shouldCreateEncodedImage {
					addTypeItem(type: "public.image", encodeUIImage: true, order: order)
					order += 1
				}
				addTypeItem(type: typeIdentifier, encodeUIImage: false, order: order)
				order += 1
			}
		}
		let p = Progress(totalUnitCount: Int64(progressChildren.count * 100))
		for c in progressChildren {
			p.addChild(c, withPendingUnitCount: 100)
		}
		return p
	}
}
