import AppKit
import GladysCommon
import GladysUI

final class GladysFilePromiseProvider: NSFilePromiseProvider {
    @MainActor
    static func provider(for component: Component, with title: String, extraItems: ContiguousArray<Component>, tags: [String]?) -> GladysFilePromiseProvider {
        let title = component.prepareFilename(name: title.dropFilenameSafe, directory: nil)
        let tempPath = temporaryDirectoryUrl.appendingPathComponent(component.uuid.uuidString).appendingPathComponent(title)

        let delegate = GladysFileProviderDelegate(item: component, title: title, tempPath: tempPath, tags: tags)

        let extra = extraItems.filter { $0.typeIdentifier != "public.file-url" }
        let p = GladysFilePromiseProvider(fileType: "public.data", delegate: delegate, extraItems: extra, strongReference: delegate, component: component, tempPath: tempPath, tags: tags)
        return p
    }

    init(fileType: String, delegate: NSFilePromiseProviderDelegate, extraItems: [Component], strongReference: GladysFileProviderDelegate?, component: Component?, tempPath: URL?, tags: [String]?) {
        self.extraItems = extraItems
        self.strongReference = strongReference
        self.component = component
        self.tempPath = tempPath
        self.tags = tags
        super.init()
        self.fileType = fileType
        self.delegate = delegate
    }

    private var extraItems: [Component]
    private var strongReference: GladysFileProviderDelegate?
    private var component: Component?
    private var tempPath: URL?
    private var tags: [String]?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        let newItems = extraItems.map { extraItem in
            let identifier = MainActor.assumeIsolated { extraItem.typeIdentifier }
            return NSPasteboard.PasteboardType(identifier)
        }
        types.insert(contentsOf: newItems, at: 0)
        let hasTempPath = tempPath != nil
        if hasTempPath {
            types.append(NSPasteboard.PasteboardType(rawValue: "public.file-url"))
        }
        return types
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        let t = type.rawValue
        if t == "public.file-url" {
            return []
        }
        let extraItemsContainsType = extraItems.contains { extraItem in
            MainActor.assumeIsolated { extraItem.typeIdentifier == t }
        } == true

        if extraItemsContainsType {
            return []
        }
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        let T = type.rawValue
        switch T {
        case "com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.NSFilePromiseID", "com.apple.pasteboard.promised-file-content-type", "com.apple.pasteboard.promised-file-name", "public.data":
            return super.pasteboardPropertyList(forType: type)
        default:
            let extraItemOfType = extraItems.first { extraItem in MainActor.assumeIsolated { extraItem.typeIdentifier } == T }
            if extraItemOfType == nil, T == "public.file-url", let component, let tempPath {
                do {
                    let tagCopy = tags
                    try MainActor.assumeIsolated {
                        try component.writeBytes(to: tempPath, tags: tagCopy)
                    }
                } catch {
                    log("Could not create drop data: \(error.localizedDescription)")
                }
                return tempPath.dataRepresentation
            } else if let extraItemOfType {
                return MainActor.assumeIsolated { extraItemOfType.bytes }
            } else {
                return nil
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

    nonisolated func filePromiseProvider(_: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            let fm = FileManager.default
            let temp = tempPath
            if !fm.fileExists(atPath: temp.path) {
                let item = typeItem
                let itemTags = tags
                try MainActor.assumeIsolated {
                    try item?.writeBytes(to: temp, tags: itemTags)
                }
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
    func writeBytes(to destinationUrl: URL, tags: [String]?) throws {
        Model.trimTemporaryDirectory()

        let directory = destinationUrl.deletingLastPathComponent()

        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } else if fm.fileExists(atPath: destinationUrl.path) {
            try fm.removeItem(at: destinationUrl)
        }

        let bytesToWrite: Data? = if let s = encodedUrl, !s.isFileURL {
            s.urlFileContent
        } else {
            dataForDropping
        }

        if let bytesToWrite {
            try bytesToWrite.write(to: destinationUrl)
        } else {
            try fm.copyItem(at: bytesPath, to: destinationUrl)
        }

        if let tags, tags.isPopulated, PersistedOptions.readAndStoreFinderTagsAsLabels {
            try? (destinationUrl as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
    }
}
