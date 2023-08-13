import CloudKit
import Foundation
import Lista
#if os(macOS)
    import Cocoa
#else
    import UIKit
#endif
import NaturalLanguage
import UniformTypeIdentifiers
#if !os(watchOS)
    import CoreSpotlight
    import Speech
    import Vision
#endif

public final class ArchivedItem: Codable {
    public let suggestedName: String?
    public let uuid: UUID
    public let createdAt: Date

    public var components: ContiguousArray<Component> {
        didSet {
            needsReIngest = true // also sets needsSaving
        }
    }

    public var updatedAt: Date {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var needsReIngest: Bool {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var needsDeletion: Bool {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var note: String {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var titleOverride: String {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var labels: [String] {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var lockPassword: Data? {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var lockHint: String? {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    public var highlightColor: ItemColor = .none {
        didSet {
            flags.insert(.needsSaving)
        }
    }

    // Transient
    public struct Flags: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let needsSaving = Flags(rawValue: 1 << 0)
        public static let needsUnlock = Flags(rawValue: 1 << 1)
        public static let isBeingCreatedBySync = Flags(rawValue: 1 << 2)
    }

    public var flags: Flags
    public var loadingProgress: Progress?

    private enum CodingKeys: String, CodingKey {
        case suggestedName
        case components = "typeItems"
        case createdAt
        case updatedAt
        case uuid
        case needsReIngest
        case note
        case titleOverride
        case labels
        case needsDeletion
        case lockPassword
        case lockHint
        case highlightColor
    }

    public func encode(to encoder: Encoder) throws {
        var v = encoder.container(keyedBy: CodingKeys.self)
        try v.encodeIfPresent(suggestedName, forKey: .suggestedName)
        try v.encode(createdAt, forKey: .createdAt)
        try v.encode(updatedAt, forKey: .updatedAt)
        try v.encode(uuid, forKey: .uuid)
        try v.encode(components, forKey: .components)
        try v.encode(needsReIngest, forKey: .needsReIngest)
        try v.encode(note, forKey: .note)
        try v.encode(titleOverride, forKey: .titleOverride)
        try v.encode(labels, forKey: .labels)
        try v.encode(needsDeletion, forKey: .needsDeletion)
        try v.encode(highlightColor, forKey: .highlightColor)
        try v.encodeIfPresent(lockPassword, forKey: .lockPassword)
        try v.encodeIfPresent(lockHint, forKey: .lockHint)
    }

    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        suggestedName = try v.decodeIfPresent(String.self, forKey: .suggestedName)
        let c = try v.decode(Date.self, forKey: .createdAt)
        createdAt = c
        updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c
        uuid = try v.decode(UUID.self, forKey: .uuid)
        components = try v.decode(ContiguousArray<Component>.self, forKey: .components)
        needsReIngest = try v.decodeIfPresent(Bool.self, forKey: .needsReIngest) ?? false
        note = try v.decodeIfPresent(String.self, forKey: .note) ?? ""
        titleOverride = try v.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        labels = try v.decodeIfPresent([String].self, forKey: .labels) ?? []
        needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
        highlightColor = try v.decodeIfPresent(ItemColor.self, forKey: .highlightColor) ?? .none
        lockHint = try v.decodeIfPresent(String.self, forKey: .lockHint)
        lockPassword = try v.decodeIfPresent(Data.self, forKey: .lockPassword)
        flags = lockPassword == nil ? [] : .needsUnlock
    }

    public init(cloning item: ArchivedItem) {
        let myUUID = UUID()
        uuid = myUUID

        createdAt = Date()
        updatedAt = createdAt
        lockPassword = nil
        highlightColor = item.highlightColor
        lockHint = nil
        needsReIngest = true
        needsDeletion = false
        flags = .needsSaving

        titleOverride = item.titleOverride
        note = item.note
        suggestedName = item.suggestedName
        labels = item.labels

        components = ContiguousArray(item.components.map {
            Component(cloning: $0, newParentUUID: myUUID)
        })
    }

    public static func importData(providers: [NSItemProvider], overrides: ImportOverrides?) -> Lista<ArchivedItem> {
        if PersistedOptions.separateItemPreference {
            let res = Lista<ArchivedItem>()
            for p in providers {
                for t in sanitised(p.registeredTypeIdentifiers) {
                    let item = ArchivedItem(providers: [p], limitToType: t, overrides: overrides)
                    res.append(item)
                }
            }
            return res

        } else {
            let item = ArchivedItem(providers: providers, limitToType: nil, overrides: overrides)
            return Lista(value: item)
        }
    }

    private init(providers: [NSItemProvider], limitToType: String?, overrides: ImportOverrides?) {
        uuid = UUID()
        createdAt = Date()
        updatedAt = createdAt
        #if os(watchOS)
            suggestedName = nil
        #else
            suggestedName = providers.first?.suggestedName
        #endif
        needsReIngest = false // original ingest, not re-ingest, show "cancel"
        needsDeletion = false
        titleOverride = overrides?.title ?? ""
        note = overrides?.note ?? ""
        labels = overrides?.labels ?? []
        components = ContiguousArray<Component>()
        flags = .needsSaving
        loadingProgress = Progress()

        Task {
            await newItemIngest(providers: providers, limitToType: limitToType)
        }
    }

    public var isTransferring: Bool {
        components.contains { $0.flags.contains(.isTransferring) }
    }

    public var goodToSave: Bool {
        !needsDeletion && !isTransferring
    }

    public var eligibleForExternalUpdateCheck: Bool {
        !(needsDeletion || needsReIngest || flags.contains(.isBeingCreatedBySync) || loadingProgress != nil || shareMode == .elsewhereReadOnly)
    }

    public init(from record: CKRecord) {
        let myUUID = UUID(uuidString: record.recordID.recordName)!
        uuid = myUUID

        createdAt = record["createdAt"] as? Date ?? .distantPast
        updatedAt = record["updatedAt"] as? Date ?? .distantPast
        titleOverride = record["titleOverride"] as? String ?? ""
        note = record["note"] as? String ?? ""

        suggestedName = record["suggestedName"] as? String
        lockPassword = record["lockPassword"] as? Data
        lockHint = record["lockHint"] as? String
        labels = (record["labels"] as? [String]) ?? []

        if let colorString = record["highlightColor"] as? String, let color = ItemColor(rawValue: colorString) {
            highlightColor = color
        } else {
            highlightColor = .none
        }

        needsReIngest = true
        needsDeletion = false
        components = []

        if lockPassword == nil {
            flags = [.isBeingCreatedBySync, .needsSaving]
        } else {
            flags = [.isBeingCreatedBySync, .needsSaving, .needsUnlock]
        }

        cloudKitRecord = record
    }
}

extension ArchivedItem: Hashable, DisplayImageProviding {
    public static func == (lhs: ArchivedItem, rhs: ArchivedItem) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    public var trimmedName: String {
        displayTitleOrUuid.truncateWithEllipses(limit: 32)
    }

    public var trimmedSuggestedName: String {
        displayTitleOrUuid.truncateWithEllipses(limit: 128)
    }

    public var sizeInBytes: Int64 {
        components.reduce(0) { $0 + $1.sizeInBytes }
    }

    public var imagePath: URL? {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.imagePath
    }

    public var displayIcon: IMAGE {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.componentIcon ?? #imageLiteral(resourceName: "iconStickyNote")
    }

    public var dominantTypeDescription: String? {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.typeDescription
    }

    public var displayMode: ArchivedDropItemDisplayType {
        let highestPriorityIconItem = components.max { $0.displayIconPriority < $1.displayIconPriority }
        return highestPriorityIconItem?.displayIconContentMode ?? .center
    }

    public var displayText: (String?, NSTextAlignment) {
        guard titleOverride.isEmpty else { return (titleOverride, .center) }
        return nonOverridenText
    }

    public var displayTitleOrUuid: String {
        displayText.0 ?? uuid.uuidString
    }

    public var isLocked: Bool {
        lockPassword != nil
    }

    public var isTemporarilyUnlocked: Bool {
        isLocked && !flags.contains(.needsUnlock)
    }

    public var associatedWebURL: URL? {
        for i in components {
            if let u = i.encodedUrl, !u.isFileURL {
                return u as URL
            }
        }
        return nil
    }

    public var imageCacheKey: String {
        "\(uuid.uuidString) \(updatedAt.timeIntervalSinceReferenceDate)"
    }

    public var nonOverridenText: (String?, NSTextAlignment) {
        if let a = components.first(where: { $0.accessoryTitle != nil })?.accessoryTitle { return (a, .center) }

        let highestPriorityItem = components.max { $0.displayTitlePriority < $1.displayTitlePriority }
        if let title = highestPriorityItem?.displayTitle {
            let alignment = highestPriorityItem?.displayTitleAlignment ?? .center
            return (title, alignment)
        } else {
            return (suggestedName, .center)
        }
    }

    public func bytes(for type: String) -> Data? {
        components.first { $0.typeIdentifier == type }?.bytes
    }

    public func url(for type: String) -> URL? {
        components.first { $0.typeIdentifier == type }?.encodedUrl
    }

    public var isVisible: Bool {
        !needsDeletion && lockPassword == nil && !needsReIngest
    }

    @MainActor
    public func markUpdated() {
        updatedAt = Date()
        needsCloudPush = true
    }

    public var folderUrl: URL {
        if let url = folderUrlCache[uuid] {
            return url as URL
        }

        let url = appStorageUrl.appendingPathComponent(uuid.uuidString)
        let f = FileManager.default
        let path = url.path
        if !f.fileExists(atPath: path) {
            try! f.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
        folderUrlCache[uuid] = url
        return url
    }

    private var cloudKitDataPath: URL {
        if let url = cloudKitDataPathCache[uuid] {
            return url as URL
        }
        let url = folderUrl.appendingPathComponent("ck-record", isDirectory: false)
        cloudKitDataPathCache[uuid] = url
        return url
    }

    private var cloudKitShareDataPath: URL {
        if let url = cloudKitShareDataPathCache[uuid] {
            return url as URL
        }
        let url = folderUrl.appendingPathComponent("ck-share", isDirectory: false)
        cloudKitShareDataPathCache[uuid] = url
        return url
    }

    private static let needsCloudPushKey = "build.bru.Gladys.needsCloudPush"
    public var needsCloudPush: Bool {
        get {
            if let cached = needsCloudPushCache[uuid] {
                return cached
            }
            let path = cloudKitDataPath
            return itemAccessQueue.sync {
                let value = FileManager.default.getBoolAttribute(ArchivedItem.needsCloudPushKey, from: path) ?? true
                needsCloudPushCache[uuid] = value
                return value
            }
        }
        set {
            needsCloudPushCache[uuid] = newValue
            let path = cloudKitDataPath
            itemAccessQueue.async(flags: .barrier) {
                FileManager.default.setBoolAttribute(ArchivedItem.needsCloudPushKey, at: path, to: newValue)
            }
        }
    }

    public enum ShareMode {
        case none, elsewhereReadOnly, elsewhereReadWrite, sharing
    }

    public var isRecentlyAdded: Bool {
        createdAt.timeIntervalSinceNow > -86400 // 24h
    }

    public var shareMode: ShareMode {
        if let shareRecord = cloudKitShareRecord {
            if shareRecord.recordID.zoneID == privateZoneId {
                .sharing
            } else if let permission = cloudKitShareRecord?.currentUserParticipant?.permission, permission == .readWrite {
                .elsewhereReadWrite
            } else {
                .elsewhereReadOnly
            }
        } else {
            .none
        }
    }

    public var isShareWithOnlyOwner: Bool {
        if let shareRecord = cloudKitShareRecord {
            return shareRecord.participants.count == 1
                && shareRecord.participants[0].userIdentity.userRecordID?.recordName == CKCurrentUserDefaultName
        }
        return false
    }

    public var isPrivateShareWithOnlyOwner: Bool {
        if let shareRecord = cloudKitShareRecord {
            return shareRecord.participants.count == 1
                && shareRecord.publicPermission == .none
                && shareRecord.participants[0].userIdentity.userRecordID?.recordName == CKCurrentUserDefaultName
        }
        return false
    }

    public var isImportedShare: Bool {
        switch shareMode {
        case .elsewhereReadOnly, .elsewhereReadWrite:
            true
        case .none, .sharing:
            false
        }
    }

    public var cloudKitRecord: CKRecord? {
        get {
            if let cached = cloudKitRecordCache[uuid] {
                return cached.record
            }
            let recordLocation = cloudKitDataPath
            return itemAccessQueue.sync {
                if let data = try? Data(contentsOf: recordLocation), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
                    let record = CKRecord(coder: coder)
                    coder.finishDecoding()
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: record)
                    return record

                } else {
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: nil)
                    return nil
                }
            }
        }
        set {
            let newEntry = CKRecordCacheEntry(record: newValue)
            cloudKitRecordCache[uuid] = newEntry
            let recordLocation = cloudKitDataPath
            itemAccessQueue.async(flags: .barrier) {
                if let newValue {
                    let coder = NSKeyedArchiver(requiringSecureCoding: true)
                    newValue.encodeSystemFields(with: coder)
                    try? coder.encodedData.write(to: recordLocation)
                    self.needsCloudPush = false
                } else {
                    let f = FileManager.default
                    let path = recordLocation.path
                    if f.fileExists(atPath: path) {
                        try? f.removeItem(atPath: path)
                    }
                }
            }
        }
    }

    public var cloudKitShareRecord: CKShare? {
        get {
            if let cached = cloudKitShareCache[uuid] {
                return cached.share
            }
            return itemAccessQueue.sync {
                if let data = try? Data(contentsOf: cloudKitShareDataPath), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
                    let share = CKShare(coder: coder)
                    coder.finishDecoding()
                    cloudKitShareCache[uuid] = CKShareCacheEntry(share: share)
                    return share

                } else {
                    cloudKitShareCache[uuid] = CKShareCacheEntry(share: nil)
                    return nil
                }
            }
        }
        set {
            cloudKitShareCache[uuid] = CKShareCacheEntry(share: newValue)
            let recordLocation = cloudKitShareDataPath
            itemAccessQueue.async(flags: .barrier) {
                if let newValue {
                    let coder = NSKeyedArchiver(requiringSecureCoding: true)
                    newValue.encodeSystemFields(with: coder)
                    try? coder.encodedData.write(to: recordLocation)
                } else {
                    let f = FileManager.default
                    let path = recordLocation.path
                    if f.fileExists(atPath: path) {
                        try? f.removeItem(atPath: path)
                    }
                }
            }
        }
    }

    private static func sanitised(_ ids: [String]) -> [String] {
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

    public var mostRelevantTypeItem: Component? {
        components.max { $0.contentPriority < $1.contentPriority }
    }

    public var mostRelevantTypeItemImage: Component? {
        let item = mostRelevantTypeItem
        if let i = item, i.typeConforms(to: .url), PersistedOptions.includeUrlImagesInMlLogic {
            return components.filter { $0.typeConforms(to: .image) }.max { $0.contentPriority < $1.contentPriority }
        }
        return item
    }

    public var mostRelevantTypeItemMedia: Component? {
        components.filter { $0.typeConforms(to: .video) || $0.typeConforms(to: .audio) }.max { $0.contentPriority < $1.contentPriority }
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

    #if !os(watchOS)
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
                    let link = temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString + "-audio-detect").appendingPathExtension(ext)
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
                await tags2.append(contentsOf: tagTask.value)
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
    #endif

    @MainActor
    private func componentIngestDone() {
        Images.shared[imageCacheKey] = nil
        loadingProgress = nil
        needsReIngest = false
        Task {
            // timing corner case
            await Task.yield()
            sendNotification(name: .IngestComplete, object: self)
        }
    }

    public func cancelIngest() {
        loadingProgress?.cancel()
        components.forEach { $0.cancelIngest() }
        log("Item \(uuid.uuidString) ingest cancelled by user")
    }

    public var loadingAborted: Bool {
        components.contains { $0.flags.contains(.loadingAborted) }
    }

    @MainActor
    public func reIngest() async {
        guard loadingProgress == nil else {
            return
        }

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

        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, *) {
            await withDiscardingTaskGroup {
                for i in components {
                    $0.addTask {
                        try? await i.reIngest()
                        p.completedUnitCount += 1
                    }
                }
            }
        } else {
            await withTaskGroup(of: Void.self) {
                for i in components {
                    $0.addTask {
                        try? await i.reIngest()
                        p.completedUnitCount += 1
                    }
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
                let list = [extractedText, "", [AnyHashable: Any]()] as [Any]
                extractedData = try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
            }
        }
        return extractedData
    }

    private func newItemIngest(providers: [NSItemProvider], limitToType: String?) async {
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
                    log("Import error: \(error.localizedDescription)")
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

        for component in components {
            if let contributedLabels = component.contributedLabels {
                for candidate in contributedLabels where !labels.contains(candidate) {
                    labels.append(candidate)
                }
                component.contributedLabels = nil
            }
        }

        #if !os(watchOS)
            let autoText = PersistedOptions.autoGenerateLabelsFromText
            let autoImage = PersistedOptions.autoGenerateLabelsFromImage
            let ocrImage = PersistedOptions.autoGenerateTextFromImage
            let transcribeAudio = PersistedOptions.transcribeSpeechFromMedia
            if autoText || autoImage || ocrImage || transcribeAudio {
                await processML(autoText: autoText, autoImage: autoImage, ocrImage: ocrImage, transcribeAudio: transcribeAudio)
            }
        #endif
        await componentIngestDone()
    }

    #if !os(watchOS)
        public var searchAttributes: CSSearchableItemAttributeSet {
            let attributes = CSSearchableItemAttributeSet(itemContentType: "build.bru.Gladys.archivedItem")
            if isLocked {
                attributes.title = lockHint
            } else {
                attributes.title = trimmedName
                attributes.textContent = displayText.0
                if note.isEmpty {
                    attributes.contentDescription = associatedWebURL?.absoluteString
                } else {
                    attributes.contentDescription = note
                }
            }
            if !labels.isEmpty { attributes.keywords = labels }
            attributes.thumbnailURL = imagePath
            attributes.providerDataTypeIdentifiers = components.map(\.typeIdentifier)
            attributes.userCurated = true
            attributes.addedDate = createdAt
            attributes.contentModificationDate = updatedAt
            return attributes
        }

        public var searchableItem: CSSearchableItem {
            CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: searchAttributes)
        }
    #endif

    public func postModified() {
        Task { @MainActor in
            sendNotification(name: .ItemModified, object: self)
        }
    }

    public func cloudKitUpdate(from record: CKRecord) {
        updatedAt = record["updatedAt"] as? Date ?? .distantPast
        titleOverride = record["titleOverride"] as? String ?? ""
        note = record["note"] as? String ?? ""

        lockPassword = record["lockPassword"] as? Data
        lockHint = record["lockHint"] as? String
        labels = (record["labels"] as? [String]) ?? []

        if let colorString = record["highlightColor"] as? String, let color = ItemColor(rawValue: colorString) {
            highlightColor = color
        } else {
            highlightColor = .none
        }

        if isLocked {
            flags.insert(.needsUnlock)
        } else {
            flags.remove(.needsUnlock)
        }

        cloudKitRecord = record
        postModified()
    }

    public var parentZone: CKRecordZone.ID {
        cloudKitRecord?.recordID.zoneID ?? privateZoneId
    }

    public var populatedCloudKitRecord: CKRecord? {
        guard needsCloudPush, !needsDeletion, goodToSave else { return nil }

        let record = cloudKitRecord ??
            CKRecord(recordType: CloudManager.RecordType.item.rawValue,
                     recordID: CKRecord.ID(recordName: uuid.uuidString, zoneID: privateZoneId))

        record.setValuesForKeys([
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "note": note,
            "titleOverride": titleOverride
        ])

        record["labels"] = labels.isEmpty ? nil : labels
        record["suggestedName"] = suggestedName
        record["lockPassword"] = lockPassword
        record["lockHint"] = lockHint
        record["highlightColor"] = highlightColor.rawValue
        return record
    }

    public var backgroundInfoObject: Any? {
        var currentItem: Any?
        var currentPriority = -1
        for item in components {
            let (newItem, newPriority) = item.backgroundInfoObject
            if let newItem, newPriority > currentPriority {
                currentItem = newItem
                currentPriority = newPriority
            }
        }
        return currentItem
    }
}
