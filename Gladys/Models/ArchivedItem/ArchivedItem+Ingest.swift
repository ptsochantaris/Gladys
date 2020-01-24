
import Foundation
#if os(iOS)
import MobileCoreServices
#endif
import GladysFramework

extension ArchivedItem {

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

    private func componentsIngested(error: (Component, Error)?) {
        #if MAC
        for component in components {
            if let contributedLabels = component.contributedLabels {
                for candidate in contributedLabels where !labels.contains(candidate) {
                    labels.append(candidate)
                }
                component.contributedLabels = nil
            }
        }
        #endif
		imageCache.removeObject(forKey: imageCacheKey)
		loadingProgress = nil
        needsReIngest = false
        
        #if MAINAPP || MAC
        if let error = error {
            genericAlert(title: "Some data from \(displayTitleOrUuid) could not be imported", message: "Error processing type " + error.0.typeIdentifier + ": " + error.1.finalDescription)
        }
        #endif

        NotificationCenter.default.post(name: .IngestComplete, object: self)
	}

	func cancelIngest() {
		components.forEach { $0.cancelIngest() }
	}

	var loadingAborted: Bool {
        return components.contains { $0.flags.contains(.loadingAborted) }
	}

	func reIngest() {
        let group = DispatchGroup()
        NotificationCenter.default.post(name: .IngestStart, object: self)

		let loadCount = components.count
        if isTemporarilyUnlocked {
            flags.remove(.needsUnlock)
        } else if isLocked {
            flags.insert(.needsUnlock)
        }
		let p = Progress(totalUnitCount: Int64(loadCount * 100))
		loadingProgress = p
        
        var loadingError: (Component, Error)?

		if loadCount == 0 { // can happen for example when all components are removed
            group.enter()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                group.leave()
			}
		} else {
            if loadCount > 1 && components.contains(where: { $0.order != 0 }) { // some type items have an order set, enforce it
				components.sort { $0.order < $1.order }
			}
			components.forEach { i in
                group.enter()
                let cp = i.reIngest { error in
                    if let error = error {
                        loadingError = (i, error)
                    }
                    group.leave()
                }
				p.addChild(cp, withPendingUnitCount: 100)
			}
		}
        
        group.notify(queue: .main) {
            self.componentsIngested(error: loadingError)
        }
	}
    
    private func extractUrlData(from provider: NSItemProvider, for type: String) -> Data? {
        var extractedData: Data?
        let g = DispatchGroup()
        g.enter()
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
            if let data = data, data.count < 16384 {
                var extractedText: String?
                if data.isPlist, let text = SafeUnarchiver.unarchive(data) as? String {
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

	func startNewItemIngest(providers: [NSItemProvider], limitToType: String?) {
        let group = DispatchGroup()
        NotificationCenter.default.post(name: .IngestStart, object: self)

		var progressChildren = [Progress]()
        var loadingError: (Component, Error)?
        
		for provider in providers {

			var identifiers = ArchivedItem.sanitised(provider.registeredTypeIdentifiers)
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

                let i = Component(typeIdentifier: finalType, parentUuid: uuid, order: order)
                group.enter()
                let p = i.startIngest(provider: finalProvider, encodeAnyUIImage: encodeUIImage, createWebArchive: createWebArchive) { error in
                    if let error = error {
                        loadingError = (i, error)
                    }
                    group.leave()
                }
				progressChildren.append(p)
				components.append(i)
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
        loadingProgress = p
        
        group.notify(queue: .main) {
            self.componentsIngested(error: loadingError)
        }
	}
}
