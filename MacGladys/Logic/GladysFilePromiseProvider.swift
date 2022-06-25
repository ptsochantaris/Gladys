import Cocoa

final class GladysFilePromiseProvider: NSFilePromiseProvider {
    static func provider(for component: Component, with title: String, extraItems: ContiguousArray<Component>, tags: [String]?) -> GladysFilePromiseProvider {
        let title = component.prepareFilename(name: title.dropFilenameSafe, directory: nil)
        let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent(component.uuid.uuidString).appendingPathComponent(title)

        let delegate = GladysFileProviderDelegate(item: component, title: title, tempPath: tempPath, tags: tags)

        let p = GladysFilePromiseProvider(fileType: "public.data", delegate: delegate)
        p.component = component
        p.tempPath = tempPath
        p.strongReference = delegate
        p.tags = tags
        p.extraItems = extraItems.filter { $0.typeIdentifier != "public.file-url" }
        return p
    }

    private var extraItems: ContiguousArray<Component>?
    private var strongReference: GladysFileProviderDelegate?
    private var component: Component?
    private var tempPath: URL?
    private var tags: [String]?

    override public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        let newItems = (extraItems ?? []).map { NSPasteboard.PasteboardType($0.typeIdentifier) }
        types.insert(contentsOf: newItems, at: 0)
        if tempPath != nil {
            types.append(NSPasteboard.PasteboardType(rawValue: "public.file-url"))
        }
        return types
    }

    override public func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        let t = type.rawValue
        if t == "public.file-url" {
            return []
        }
        for e in extraItems ?? [] where t == e.typeIdentifier {
            return []
        }
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    @MainActor
    override public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        let T = type.rawValue
        switch T {
        case "com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.NSFilePromiseID", "com.apple.pasteboard.promised-file-content-type", "com.apple.pasteboard.promised-file-name", "public.data":
            return super.pasteboardPropertyList(forType: type)
        default:
            let item = extraItems?.first { $0.typeIdentifier == T }
            if item == nil, T == "public.file-url", let component = component, let tempPath = tempPath {
                do {
                    try component.writeBytes(to: tempPath, tags: tags)
                } catch {
                    log("Could not create drop data: \(error.localizedDescription)")
                }
                return tempPath.dataRepresentation
            } else {
                return item?.bytes
            }
        }
    }
}

final class GladysFileProviderDelegate: NSObject, NSFilePromiseProviderDelegate {
    private weak var typeItem: Component?
    private let title: String
    private let tempPath: URL
    private let tags: [String]?

    init(item: Component, title: String, tempPath: URL, tags: [String]?) {
        typeItem = item
        self.tags = tags
        self.title = title
        self.tempPath = tempPath
        super.init()
    }

    func filePromiseProvider(_: NSFilePromiseProvider, fileNameForType _: String) -> String {
        title
    }

    @MainActor
    func filePromiseProvider(_: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: tempPath.path) {
                try typeItem?.writeBytes(to: tempPath, tags: tags)
            }
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tempPath, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

private extension Component {
    @MainActor
    func writeBytes(to destinationUrl: URL, tags: [String]?) throws {
        Model.trimTemporaryDirectory()

        let directory = destinationUrl.deletingLastPathComponent()

        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } else if fm.fileExists(atPath: destinationUrl.path) {
            try fm.removeItem(at: destinationUrl)
        }

        let bytesToWrite: Data?

        if let s = encodedUrl, !s.isFileURL {
            bytesToWrite = s.urlFileContent
        } else {
            bytesToWrite = dataForDropping
        }

        if let bytesToWrite = bytesToWrite {
            try bytesToWrite.write(to: destinationUrl)
        } else {
            try fm.copyItem(at: bytesPath, to: destinationUrl)
        }

        if let tags = tags, !tags.isEmpty, PersistedOptions.readAndStoreFinderTagsAsLabels {
            try? (destinationUrl as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
    }
}
