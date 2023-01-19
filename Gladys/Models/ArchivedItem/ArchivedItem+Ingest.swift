import Foundation
#if os(macOS)
#else
    import MobileCoreServices
#endif
import GladysCommon
import NaturalLanguage
import Speech
import Vision

extension ArchivedItem {
    var mostRelevantTypeItem: Component? {
        components.max { $0.contentPriority < $1.contentPriority }
    }

    var mostRelevantTypeItemImage: Component? {
        let item = mostRelevantTypeItem
        if let i = item, i.typeConforms(to: .url), PersistedOptions.includeUrlImagesInMlLogic {
            return components.filter { $0.typeConforms(to: .image) }.max { $0.contentPriority < $1.contentPriority }
        }
        return item
    }

    var mostRelevantTypeItemMedia: Component? {
        components.filter { $0.typeConforms(to: .video) || $0.typeConforms(to: .audio) }.max { $0.contentPriority < $1.contentPriority }
    }

    static func sanitised(_ ids: [String]) -> [String] {
        let blockedSuffixes = [".useractivity", ".internalMessageTransfer", ".internalEMMessageListItemTransfer", "itemprovider", ".rtfd", ".persisted"]
        var identifiers = ids.filter { typeIdentifier in
            #if os(macOS)
                if typeIdentifier.hasPrefix("dyn.") {
                    return false
                }
                guard let type = UTType(typeIdentifier) else {
                    return false
                }
                if !(type.conforms(to: .item) || type.conforms(to: .content)) {
                    return false
                }
            #endif
            return !blockedSuffixes.contains { typeIdentifier.hasSuffix($0) }
        }
        if identifiers.contains("com.apple.mail.email") {
            identifiers.removeAll { $0 == "public.utf8-plain-text" || $0 == "com.apple.flat-rtfd" || $0 == "com.apple.uikit.attributedstring" }
        }
        return identifiers
    }

    private var imageOfImageComponentIfExists: CGImage? {
        if let firstImageComponent = mostRelevantTypeItemImage, firstImageComponent.typeConforms(to: .image), let image = IMAGE(contentsOfFile: firstImageComponent.bytesPath.path) {
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

    private func processML(autoText: Bool, autoImage: Bool, ocrImage: Bool, transcribeAudio: Bool) async {
        let finalTitle = displayText.0
        var transcribedText: String?
        let img = imageOfImageComponentIfExists
        let mediaInfo = urlOfMediaComponentIfExists

        var tags1 = [String]()
        var tags2 = [String]()

        if autoImage || ocrImage, displayMode == .fill, let img {
            var visualRequests = [VNImageBasedRequest]()
            var speechTask: SFSpeechRecognitionTask?

            if autoImage {
                let r = VNClassifyImageRequest { request, _ in
                    if let observations = request.results as? [VNClassificationObservation] {
                        let relevant = observations.filter {
                            $0.hasMinimumPrecision(0.7, forRecall: 0)
                        }.map { $0.identifier.replacingOccurrences(of: "_other", with: "").replacingOccurrences(of: "_", with: " ").capitalized }
                        tags1.append(contentsOf: relevant)
                    }
                }
                visualRequests.append(r)
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
                visualRequests.append(r)
            }

            if !visualRequests.isEmpty {
                let vr = visualRequests
                let handler = VNImageRequestHandler(cgImage: img)
                await Task.detached {
                    try? handler.perform(vr)
                }.value
            }

            if transcribeAudio, let (mediaUrl, ext) = mediaInfo, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                log("Will treat media file as \(ext) file for audio transcribing")
                let link = Model.temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString + "-audio-detect").appendingPathExtension(ext)
                try? FileManager.default.linkItem(at: mediaUrl, to: link)
                let request = SFSpeechURLRecognitionRequest(url: link)
                request.requiresOnDeviceRecognition = true

                do {
                    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                        speechTask = recognizer.recognitionTask(with: request) { result, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else if let result, result.isFinal {
                                continuation.resume(with: .success(result))
                            }
                        }
                    }
                    let detectedText = result.bestTranscription.formattedString
                    if !detectedText.isEmpty {
                        transcribedText = detectedText
                    }
                } catch {
                    log("Error transcribing media: \(error.localizedDescription)")
                }
                try? FileManager.default.removeItem(at: link)
            }

            let vr = visualRequests
            let st = speechTask
            loadingProgress?.cancellationHandler = {
                vr.forEach { $0.cancel() }
                st?.cancel()
            }
        }

        if autoText, let finalTitle = transcribedText ?? finalTitle {
            let tagTask = Task.detached { () -> [String] in
                let tagger = NLTagger(tagSchemes: [.nameType])
                tagger.string = finalTitle
                let range = finalTitle.startIndex ..< finalTitle.endIndex
                let results = tagger.tags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitOther, .omitPunctuation, .joinNames])
                return results.compactMap { token -> String? in
                    guard let tag = token.0 else { return nil }
                    switch tag {
                    case .noun, .organizationName, .personalName, .placeName:
                        return String(finalTitle[token.1])
                    default:
                        return nil
                    }
                }
            }
            tags2.append(contentsOf: await tagTask.value)
        }

        if let t = transcribedText {
            let data = Data(t.utf8)
            let newComponent = Component(typeIdentifier: UTType.utf8PlainText.identifier, parentUuid: uuid, data: data, order: 0)
            newComponent.accessoryTitle = t
            components.insert(newComponent, at: 0)
        }

        let newTags = tags1 + tags2
        for tag in newTags where !labels.contains(tag) {
            labels.append(tag)
        }
    }

    @MainActor
    private func componentIngestDone() {
        Images.shared[imageCacheKey] = nil
        loadingProgress = nil
        needsReIngest = false
        sendNotification(name: .IngestComplete, object: self)
    }

    func cancelIngest() {
        loadingProgress?.cancel()
        components.forEach { $0.cancelIngest() }
        log("Item \(uuid.uuidString) ingest cancelled by user")
    }

    var loadingAborted: Bool {
        components.contains { $0.flags.contains(.loadingAborted) }
    }

    @MainActor
    func reIngest() async {
        sendNotification(name: .IngestStart, object: self)

        let loadCount = components.count
        if isTemporarilyUnlocked {
            flags.remove(.needsUnlock)
        } else if isLocked {
            flags.insert(.needsUnlock)
        }
        let p = Progress(totalUnitCount: Int64(loadCount))
        loadingProgress = p

        if loadCount > 1, components.contains(where: { $0.order != 0 }) { // some type items have an order set, enforce it
            components.sort { $0.order < $1.order }
        }

        await withTaskGroup(of: Void.self) { group in
            for i in components {
                group.addTask {
                    try? await i.reIngest()
                    p.completedUnitCount += 1
                }
            }
        }

        componentIngestDone()
    }

    private func extractUrlData(from provider: NSItemProvider, for type: String) async -> Data? {
        var extractedData: Data?
        let data = try? await provider.loadDataRepresentation(for: type)
        if let data, data.count < 16384 {
            var extractedText: String?
            if data.isPlist, let text = SafeArchiving.unarchive(data) as? String {
                extractedText = text

            } else if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                extractedText = text
            }

            if let extractedText, extractedText.hasPrefix("http://") || extractedText.hasPrefix("https://") {
                extractedData = try? PropertyListSerialization.data(fromPropertyList: [extractedText, "", [:]], format: .binary, options: 0)
            }
        }
        return extractedData
    }

    func newItemIngest(providers: [NSItemProvider], limitToType: String?) async {
        await sendNotification(name: .IngestStart, object: self)

        var componentsThatFailed = [Component]()

        for provider in providers {
            var identifiers = ArchivedItem.sanitised(provider.registeredTypeIdentifiers)
            let shouldCreateEncodedImage = identifiers.contains("public.image") && !identifiers.contains { $0.hasPrefix("public.image.") }
            let shouldArchiveUrls = PersistedOptions.autoArchiveUrlComponents && !identifiers.contains("com.apple.webarchive")
            let alreadyHasUrl = identifiers.contains("public.url")

            if let limit = limitToType {
                identifiers = [limit]
            }

            func addTypeItem(type: String, encodeUIImage: Bool, createWebArchive: Bool, order: Int) async {
                // replace provider if we want to convert strings to URLs
                var finalProvider = provider
                var finalType = type
                if !alreadyHasUrl,
                   let utiType = UTType(type),
                   utiType.conforms(to: .text),
                   PersistedOptions.automaticallyDetectAndConvertWebLinks,
                   let extractedLinkData = await extractUrlData(from: provider, for: type) {
                    finalType = UTType.url.identifier
                    finalProvider = NSItemProvider()
                    finalProvider.registerDataRepresentation(forTypeIdentifier: finalType, visibility: .all) { provide -> Progress? in
                        provide(extractedLinkData, nil)
                        return nil
                    }
                }

                let i = Component(typeIdentifier: finalType, parentUuid: uuid, order: order)
                let p = Progress()
                loadingProgress?.totalUnitCount += 2
                loadingProgress?.addChild(p, withPendingUnitCount: 2)
                do {
                    try await i.startIngest(provider: finalProvider, encodeAnyUIImage: encodeUIImage, createWebArchive: createWebArchive, progress: p)
                } catch {
                    componentsThatFailed.append(i)
                    log("Import error: \(error.finalDescription)")
                }
                components.append(i)
            }

            var order = 0
            for typeIdentifier in identifiers {
                if typeIdentifier == "public.image", shouldCreateEncodedImage {
                    await addTypeItem(type: "public.image", encodeUIImage: true, createWebArchive: false, order: order)
                    order += 1
                }

                await addTypeItem(type: typeIdentifier, encodeUIImage: false, createWebArchive: false, order: order)
                order += 1

                if typeIdentifier == "public.url", shouldArchiveUrls {
                    await addTypeItem(type: "com.apple.webarchive", encodeUIImage: false, createWebArchive: true, order: order)
                    order += 1
                }
            }
        }

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
            await processML(autoText: autoText, autoImage: autoImage, ocrImage: ocrImage, transcribeAudio: transcribeAudio)
        }
        await componentIngestDone()
    }
}
