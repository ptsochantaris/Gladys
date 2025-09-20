import Combine
import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
    import AppKit
#endif

extension NSItemProvider: @retroactive @unchecked Sendable {}

public final class DataImporter: Sendable {
    public let identifiers: [String]
    public let suggestedName: String?

    private let dataLookupTask: Task<[String: Data], Never>

    public init(itemProvider: NSItemProvider) {
        let identifierList = Self.sanitised(itemProvider.registeredTypeIdentifiers)
        identifiers = identifierList

        #if os(watchOS)
            suggestedName = nil
        #else
            suggestedName = itemProvider.suggestedName
        #endif

        dataLookupTask = Task { @concurrent in
            await withTaskGroup { group in
                for identifier in identifierList {
                    group.addTask {
                        await withCheckedContinuation { (continuation: CheckedContinuation<(String, Data)?, Never>) in
                            itemProvider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                                if let data {
                                    continuation.resume(returning: (identifier, data))
                                } else if let error {
                                    log("Warning: Error during data read (identifier: '\(identifier)'): \(error.localizedDescription)")
                                    continuation.resume(returning: nil)
                                } else {
                                    continuation.resume(returning: nil)
                                }
                            }
                        }
                    }
                }
                var builder = [String: Data](minimumCapacity: identifierList.count)
                for await pair in group {
                    if let pair {
                        builder[pair.0] = pair.1
                    }
                }
                return builder
            }
        }
    }

    public var dataLookup: [String: Data] {
        get async {
            await dataLookupTask.value
        }
    }

    #if canImport(AppKit)
        public init(pasteboardItem: NSPasteboardItem, suggestedName: String?) {
            var lookup = [String: Data](minimumCapacity: pasteboardItem.types.count)
            for type in pasteboardItem.types {
                lookup[type.rawValue] = pasteboardItem.data(forType: type)
            }
            identifiers = Array(lookup.keys)
            self.suggestedName = suggestedName
            dataLookupTask = Task { lookup }
        }
    #endif

    public init(type: String, data: Data, suggestedName: String?) {
        identifiers = [type]
        dataLookupTask = Task { [type: data] }
        self.suggestedName = suggestedName
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
