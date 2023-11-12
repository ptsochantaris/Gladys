import Combine
import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
    import AppKit
#endif

public final class DataImporter {
    private var dataItemPublisher = CurrentValueSubject<[String: Data]?, Never>(nil)

    public var identifiers: [String]

    public var suggestedName: String?

    public init(itemProvider: NSItemProvider) {
        identifiers = Self.sanitised(itemProvider.registeredTypeIdentifiers)
        #if os(watchOS)
            suggestedName = nil
        #else
            suggestedName = itemProvider.suggestedName
        #endif

        var dataLookup = [String: Data](minimumCapacity: identifiers.count)
        let constructionQueue = DispatchQueue(label: "build.bru.data-importer")

        let group = DispatchGroup()
        for identifier in identifiers {
            group.enter()
            itemProvider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                constructionQueue.async {
                    if let error {
                        log("Warning: Error during data read (identifier: '\(identifier)'): \(error.localizedDescription)")
                    }
                    dataLookup[identifier] = data
                    group.leave()
                }
            }
        }
        group.notify(queue: constructionQueue) { [weak self] in
            guard let self else { return }
            dataItemPublisher.send(dataLookup)
        }
    }

    #if canImport(AppKit)
        public init(pasteboardItem: NSPasteboardItem, suggestedName: String?) {
            var dataLookup = [String: Data](minimumCapacity: pasteboardItem.types.count)
            for type in pasteboardItem.types {
                dataLookup[type.rawValue] = pasteboardItem.data(forType: type)
            }
            identifiers = Array(dataLookup.keys)
            self.suggestedName = suggestedName
            dataItemPublisher.send(dataLookup)
        }
    #endif

    public init(type: String, data: Data, suggestedName: String?) {
        identifiers = [type]
        self.suggestedName = suggestedName
        dataItemPublisher.send([type: data])
    }

    public func data(for identifier: String) async throws -> Data {
        if let value = dataItemPublisher.value {
            if let data = value[identifier] {
                return data
            } else {
                throw GladysError.noData
            }
        }
        var cancellable: Cancellable?
        let data = await withCheckedContinuation { continuation in
            cancellable = dataItemPublisher.compactMap { $0 }.sink { value in
                continuation.resume(returning: value)
            }
        }
        return try withExtendedLifetime(cancellable) {
            if let data = data[identifier] {
                data
            } else {
                throw GladysError.noData
            }
        }
    }

    private static func sanitised(_ ids: [String]) -> [String] {
        let blockedSuffixes = [".useractivity", ".internalMessageTransfer", ".internalEMMessageListItemTransfer", "itemprovider", ".rtfd", ".persisted"]
        var identifiers = ids.filter { typeIdentifier in
            if typeIdentifier.hasPrefix("dyn.") || typeIdentifier.contains(" ") {
                return false
            }
            guard let type = UTType(typeIdentifier), type.conforms(to: .item) || type.conforms(to: .content), !blockedSuffixes.contains(where: { typeIdentifier.hasSuffix($0) }) else {
                return false
            }
            return true
        }
        if identifiers.contains("com.apple.mail.email") {
            identifiers.removeAll { $0 == "public.utf8-plain-text" || $0 == "com.apple.flat-rtfd" || $0 == "com.apple.uikit.attributedstring" }
        }
        log("Sanitised identifiers: \(identifiers.joined(separator: ", "))")
        return identifiers
    }
}
