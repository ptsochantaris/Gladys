
import Foundation
#if os(iOS)
import MobileCoreServices
#endif

extension ArchivedDropItem: ComponentIngestionDelegate {

	static func sanitised(_ ids: [String]) -> [String] {
        let blockedSuffixes = [".useractivity", ".internalMessageTransfer", ".internalEMMessageListItemTransfer", "itemprovider", ".rtfd", ".persisted"]
		var identifiers = ids.filter { typeIdentifier in
			#if os(OSX) // TODO: perhaps do this on iOS too?
			let cfid = typeIdentifier as CFString
			if !(UTTypeConformsTo(cfid, kUTTypeItem) || UTTypeConformsTo(cfid, kUTTypeContent)) { return false }
			#endif
			return !blockedSuffixes.contains { typeIdentifier.hasSuffix($0) }
		}
        if identifiers.contains("com.apple.mail.email") {
            identifiers.removeAll { $0 == "public.utf8-plain-text" || $0 == "com.apple.flat-rtfd" || $0 == "com.apple.uikit.attributedstring" }
        }
        return identifiers
	}

	func componentIngested(typeItem: ArchivedDropItemType?) {
		loadCount = loadCount - 1
		if loadCount > 0 { return } // more to go

		if let contributedLabels = typeItem?.contributedLabels {
			for candidate in contributedLabels where !labels.contains(candidate) {
				labels.append(candidate)
			}
			typeItem?.contributedLabels = nil
		}
		imageCache.removeObject(forKey: imageCacheKey)
		loadingProgress = nil
        needsReIngest = false

        #if MAINAPP
        reIndex {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .IngestComplete, object: self)
            }
        }
        #else
        NotificationCenter.default.post(name: .IngestComplete, object: self)
        #endif
	}

	func cancelIngest() {
		typeItems.forEach { $0.cancelIngest() }
	}

	var loadingAborted: Bool {
		return typeItems.contains { $0.loadingAborted }
	}

	func reIngest() {
        NotificationCenter.default.post(name: .IngestStart, object: self)

		loadCount = typeItems.count
		let wasExplicitlyUnlocked = lockPassword != nil && !needsUnlock
		needsUnlock = lockPassword != nil && !wasExplicitlyUnlocked
		let p = Progress(totalUnitCount: Int64(loadCount * 100))
		loadingProgress = p
		if typeItems.count == 0 { // can happen for example when all components are removed
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				self.componentIngested(typeItem: nil)
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
    
    private func extractUrlData(from provider: NSItemProvider, for type: String) -> Data? {
        var extractedData: Data?
        let g = DispatchGroup()
        g.enter()
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
            if let data = data, data.count < 16384 {
                var extractedText: String?
                if data.isPlist, let text = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? String {
                    extractedText = text
                    
                } else if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    extractedText = text
                }
                if let extractedText = extractedText, extractedText.hasPrefix("http://") || extractedText.hasPrefix("https://") {
                    extractedData = try? PropertyListSerialization.data(fromPropertyList: [extractedText, "", [:]], format: .binary, options: 0)
                }
            }
            g.leave()
        }
        g.wait()
        return extractedData
    }

	func startNewItemIngest(providers: [NSItemProvider], limitToType: String?) -> Progress {
        
        NotificationCenter.default.post(name: .IngestStart, object: self)

		var progressChildren = [Progress]()

		for provider in providers {

			var identifiers = ArchivedDropItem.sanitised(provider.registeredTypeIdentifiers)
			let shouldCreateEncodedImage = identifiers.contains("public.image") && !identifiers.contains { $0.hasPrefix("public.image.") }
			let shouldArchiveUrls = PersistedOptions.autoArchiveUrlComponents && !identifiers.contains("com.apple.webarchive")
            let alreadyHasUrl = identifiers.contains("public.url")
            
			if let limit = limitToType {
				identifiers = [limit]
			}

			func addTypeItem(type: String, encodeUIImage: Bool, createWebArchive: Bool, order: Int) {
                
                // replace provider if we want to convert strings to URLs
                var finalProvider = provider
                var finalType = type
                if !alreadyHasUrl,
                    UTTypeConformsTo(type as CFString, kUTTypeText),
                    PersistedOptions.automaticallyDetectAndConvertWebLinks,
                    let extractedLinkData = extractUrlData(from: provider, for: type) {
                    
                    finalType = kUTTypeURL as String
                    finalProvider = NSItemProvider()
                    finalProvider.registerDataRepresentation(forTypeIdentifier: finalType, visibility: .all) { provide -> Progress? in
                        provide(extractedLinkData, nil)
                        return nil
                    }
                }

                loadCount += 1
                let i = ArchivedDropItemType(typeIdentifier: finalType, parentUuid: uuid, delegate: self, order: order)
				let p = i.startIngest(provider: finalProvider, delegate: self, encodeAnyUIImage: encodeUIImage, createWebArchive: createWebArchive)
				progressChildren.append(p)
				typeItems.append(i)
			}

			var order = 0
			for typeIdentifier in identifiers {
				if typeIdentifier == "public.image" && shouldCreateEncodedImage {
					addTypeItem(type: "public.image", encodeUIImage: true, createWebArchive: false, order: order)
					order += 1
				}

				addTypeItem(type: typeIdentifier, encodeUIImage: false, createWebArchive: false, order: order)
				order += 1

				if typeIdentifier == "public.url" && shouldArchiveUrls {
					addTypeItem(type: "com.apple.webarchive", encodeUIImage: false, createWebArchive: true, order: order)
					order += 1
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
