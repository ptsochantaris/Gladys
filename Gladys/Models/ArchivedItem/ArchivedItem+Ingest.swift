import Foundation
#if os(iOS)
import MobileCoreServices
#endif
import GladysFramework
import NaturalLanguage
import Vision
import Speech

extension ArchivedItem {
    
    var mostRelevantTypeItem: Component? {
        return components.max { $0.contentPriority < $1.contentPriority }
    }

    var mostRelevantTypeItemImage: Component? {
        let item = mostRelevantTypeItem
        if let i = item, i.typeConforms(to: kUTTypeURL), PersistedOptions.includeUrlImagesInMlLogic {
            return components.filter { $0.typeConforms(to: kUTTypeImage) }.max { $0.contentPriority < $1.contentPriority }
        }
        return item
    }

    var mostRelevantTypeItemMedia: Component? {
        return components.filter { $0.typeConforms(to: kUTTypeVideo) || $0.typeConforms(to: kUTTypeAudio) }.max { $0.contentPriority < $1.contentPriority }
    }
    
	static func sanitised(_ ids: [String]) -> [String] {
        let blockedSuffixes = [".useractivity", ".internalMessageTransfer", ".internalEMMessageListItemTransfer", "itemprovider", ".rtfd", ".persisted"]
		var identifiers = ids.filter { typeIdentifier in
			#if os(OSX)
            if typeIdentifier.hasPrefix("dyn.") {
                return false
            }
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
        if let firstImageComponent = mostRelevantTypeItemImage, firstImageComponent.typeConforms(to: kUTTypeImage), let image = IMAGE(contentsOfFile: firstImageComponent.bytesPath.path) {
            #if os(macOS)
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #else
                return image.cgImage
            #endif
        }
        return nil
    }
    
    private var urlOfMediaComponentIfExists: (URL, String)? {
        if let component = mostRelevantTypeItemMedia, let ext = component.fileExtension {
            return (component.bytesPath, ext)
        }
        return nil
    }

    private func initialIngestComplete() {
        components.removeAll { !$0.dataExists }

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
        let ocrImage = PersistedOptions.autoGenerateTextFromImage
        let transcribeAudio = PersistedOptions.transcribeSpeechFromMedia
        if autoText || autoImage || ocrImage || transcribeAudio {
            processML(autoText: autoText, autoImage: autoImage, ocrImage: ocrImage, transcribeAudio: transcribeAudio)
        } else {
            componentIngestDone()
        }
	}
    
    private func processML(autoText: Bool, autoImage: Bool, ocrImage: Bool, transcribeAudio: Bool) {
        let finalTitle = displayText.0
        var transcribedText: String?
        let img: CGImage?
        let mediaInfo: (URL, String)?
        #if os(macOS)
            if #available(OSX 10.15, *) {
                img = imageOfImageComponentIfExists
                mediaInfo = urlOfMediaComponentIfExists
            } else {
                img = nil
                mediaInfo = nil
            }
        #else
            img = imageOfImageComponentIfExists
            mediaInfo = urlOfMediaComponentIfExists
        #endif

        let group = DispatchGroup()
        var tags1 = [String]()
        var tags2 = [String]()

        if #available(OSX 10.15, *) {
            
            var ocrRequests = [VNImageBasedRequest]()
            var speechTask: SFSpeechRecognitionTask?

            if (autoImage || ocrImage), displayMode == .fill, let img = img {
                
                if autoImage {
                    let r = VNClassifyImageRequest { request, _ in
                        if let observations = request.results as? [VNClassificationObservation] {
                            let relevant = observations.filter {
                                $0.hasMinimumPrecision(0.7, forRecall: 0)
                            }.map { $0.identifier.replacingOccurrences(of: "_other", with: "").replacingOccurrences(of: "_", with: " ").capitalized }
                            tags1.append(contentsOf: relevant)
                        }
                    }
                    ocrRequests.append(r)
                }
                
                if ocrImage {
                    let r = VNRecognizeTextRequest { request, _ in
                        if let observations = request.results as? [VNRecognizedTextObservation] {
                            let detectedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !detectedText.isEmpty {
                                transcribedText = detectedText
                            }
                        }
                    }
                    r.recognitionLevel = .accurate
                    ocrRequests.append(r)
                }
                
                if !ocrRequests.isEmpty {
                    let handler = VNImageRequestHandler(cgImage: img)
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        try? handler.perform(ocrRequests)
                        group.leave()
                    }
                }
            }
            
            if transcribeAudio, let (mediaUrl, ext) = mediaInfo, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                group.enter()
                log("Will treat media file as \(ext) file for audio transcribing")
                let link = Model.temporaryDirectoryUrl.appendingPathComponent(self.uuid.uuidString + "-audio-detect").appendingPathExtension(ext)
                try? FileManager.default.linkItem(at: mediaUrl, to: link)
                let request = SFSpeechURLRecognitionRequest(url: link)
                request.requiresOnDeviceRecognition = true
                speechTask = recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        log("Error transcribing media: \(error.localizedDescription)")
                        try? FileManager.default.removeItem(at: link)
                        group.leave()
                    } else if let result = result, result.isFinal {
                        let detectedText = result.bestTranscription.formattedString
                        if !detectedText.isEmpty {
                            transcribedText = detectedText
                        }
                        try? FileManager.default.removeItem(at: link)
                        group.leave()
                    }
                }
            }
            
            loadingProgress?.cancellationHandler = {
                ocrRequests.forEach { $0.cancel() }
                speechTask?.cancel()
            }
        }
        
        let finalGroup = DispatchGroup()
        finalGroup.enter()
        group.notify(queue: .global(qos: .utility)) {
            if autoText, let finalTitle = transcribedText ?? finalTitle {
                let tagger = NLTagger(tagSchemes: [.nameType])
                tagger.string = finalTitle
                let range = finalTitle.startIndex ..< finalTitle.endIndex
                let results = tagger.tags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitOther, .omitPunctuation, .joinNames])
                let textTags = results.compactMap { token -> String? in
                    guard let tag = token.0 else { return nil }
                    switch tag {
                    case .placeName, .personalName, .organizationName, .noun:
                        return String(finalTitle[token.1])
                    default:
                        return nil
                    }
                }
                tags2.append(contentsOf: textTags)
                finalGroup.leave()
            } else {
                finalGroup.leave()
            }
        }
        
        finalGroup.notify(queue: .main) {
            if let t = transcribedText, let data = t.data(using: .utf8) {
                let newComponent = Component(typeIdentifier: kUTTypeUTF8PlainText as String, parentUuid: self.uuid, data: data, order: 0)
                newComponent.accessoryTitle = t
                self.components.insert(newComponent, at: 0)
            }
            let newTags = tags1 + tags2
            for tag in newTags where !self.labels.contains(tag) {
                self.labels.append(tag)
            }
            self.componentIngestDone()
        }
    }
    
    private func componentIngestDone() {
        imageCache.removeObject(forKey: imageCacheKey)
        loadingProgress = nil
        needsReIngest = false
        NotificationCenter.default.post(name: .IngestComplete, object: self)
    }

	func cancelIngest() {
        loadingProgress?.cancel()
		components.forEach { $0.cancelIngest() }
        log("Item \(uuid.uuidString) ingest cancelled by user")
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
                let cp = i.reIngest { _ in
                    group.leave()
                }
				p.addChild(cp, withPendingUnitCount: 100)
			}
		}
        
        group.notify(queue: .main) {
            self.componentIngestDone()
            completionGroup?.leave()
        }
	}
    
    private func extractUrlData(from provider: NSItemProvider, for type: String) -> Data? {
        var extractedData: Data?
        let sem = DispatchSemaphore(value: 0)
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
            sem.signal()
        }
        sem.wait()
        return extractedData
    }

	func startNewItemIngest(providers: [NSItemProvider], limitToType: String?) {
        let group = DispatchGroup()
        NotificationCenter.default.post(name: .IngestStart, object: self)

		var progressChildren = [Progress]()
        var componentsThatFailed = [Component]()
        
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
                        componentsThatFailed.append(i)
                        log("Import error: \(error.finalDescription)")
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
            self.initialIngestComplete()
        }
	}
}
