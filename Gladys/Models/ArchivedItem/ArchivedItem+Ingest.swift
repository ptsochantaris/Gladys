import Foundation
#if os(iOS)
import MobileCoreServices
#endif
import GladysFramework
import NaturalLanguage
import Vision

extension ArchivedItem {
    
    var mostRelevantTypeItem: Component? {
        return components.max { $0.contentPriority < $1.contentPriority }
    }

	static func sanitised(_ ids: [String]) -> [String] {
        let blockedSuffixes = [".useractivity", ".internalMessageTransfer", ".internalEMMessageListItemTransfer", "itemprovider", ".rtfd", ".persisted"]
		var identifiers = ids.filter { typeIdentifier in
			#if os(OSX)
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
    
    private var imageOfImageComponentIfExists: CGImage? {
        if let firstImageComponent = mostRelevantTypeItem, firstImageComponent.typeConforms(to: kUTTypeImage), let image = IMAGE(contentsOfFile: firstImageComponent.bytesPath.path) {
            #if os(macOS)
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #else
                return image.cgImage
            #endif
        }
        return nil
    }

    private func componentsIngested(wasInitialIngest: Bool, error: (Component, Error)?) {
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
        
        let autoText = PersistedOptions.autoGenerateLabelsFromText
        let autoImage = PersistedOptions.autoGenerateLabelsFromImage
        if #available(OSX 10.14, iOS 13.0, *), wasInitialIngest, error == nil, autoText || autoImage {
            let finalTitle = displayText.0
            let img: CGImage?
            #if os(macOS)
                if #available(OSX 10.15, *) {
                    img = imageOfImageComponentIfExists
                } else {
                    img = nil
                }
            #else
                img = imageOfImageComponentIfExists
            #endif
            let mode = displayMode
            Component.ingestQueue.async {
                var tags = [String]()
                if autoText, let finalTitle = finalTitle {
                    let tagger = NLTagger(tagSchemes: [.nameType])
                    tagger.string = finalTitle
                    let range = finalTitle.startIndex ..< finalTitle.endIndex
                    let textTags = tagger.tags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitOther, .omitPunctuation, .joinNames]).compactMap { token -> String? in
                        guard let tag = token.0 else { return nil }
                        switch tag {
                        case .placeName, .personalName, .organizationName, .noun:
                            return String(finalTitle[token.1])
                        default:
                            return nil
                        }
                    }
                    tags.append(contentsOf: textTags)
                }
                
                if #available(OSX 10.15, iOS 13.0, *), autoImage, mode == .fill, let img = img {
                    let handler = VNImageRequestHandler(cgImage: img)
                    let request = VNClassifyImageRequest()
                    try? handler.perform([request])
                    if let observations = request.results as? [VNClassificationObservation] {
                        let relevant = observations.filter {
                            $0.hasMinimumPrecision(0.7, forRecall: 0)
                        }.map { $0.identifier.replacingOccurrences(of: "_other", with: "").replacingOccurrences(of: "_", with: " ").capitalized }
                        tags.append(contentsOf: relevant)
                    }
                }
                
                DispatchQueue.main.async {
                    for tag in tags where !self.labels.contains(tag) {
                        self.labels.append(tag)
                    }
                    self.componentIngestDone(error: error)
                }
            }
        } else {
            componentIngestDone(error: error)
        }
	}
    
    private func componentIngestDone(error: (Component, Error)?) {
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

    func reIngest(completionGroup: DispatchGroup? = nil) {
        completionGroup?.enter()
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
            self.componentsIngested(wasInitialIngest: false, error: loadingError)
            completionGroup?.leave()
        }
	}
    
    private func extractUrlData(from provider: NSItemProvider, for type: String) -> Data? {
        var extractedData: Data?
        let g = DispatchGroup()
        g.enter()
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
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
            self.componentsIngested(wasInitialIngest: true, error: loadingError)
        }
	}
}
