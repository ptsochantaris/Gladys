import Cocoa
import Contacts
import ContactsUI
import MapKit
import UniformTypeIdentifiers
import ZIPFoundation

extension Component {
    var isArchivable: Bool {
        if let e = encodedUrl, !e.isFileURL, e.host != nil, let s = e.scheme, s.hasPrefix("http") {
            return true
        } else {
            return false
        }
    }

    var componentIcon: NSImage? {
        get {
            guard let d = try? Data(contentsOf: imagePath), let i = NSImage(data: d) else {
                return nil
            }
            if displayIconTemplate {
                i.isTemplate = true
                let w = i.size.width
                let h = i.size.height
                let scale = min(32.0 / h, 32.0 / w)
                i.size = NSSize(width: w * scale, height: h * scale)
            }
            return i
        }
        set {
            let ipath = imagePath
            if let n = newValue, let data = n.tiffRepresentation {
                try? data.write(to: ipath)
            } else if FileManager.default.fileExists(atPath: ipath.path) {
                try? FileManager.default.removeItem(at: ipath)
            }
        }
    }

    private func appendDirectory(_ baseURL: URL, chain: [String], archive: Archive, fm: FileManager) throws {
        let joinedChain = chain.joined(separator: "/")
        let dirURL = baseURL.appendingPathComponent(joinedChain)
        for file in try fm.contentsOfDirectory(atPath: dirURL.path) {
            if flags.contains(.loadingAborted) {
                log("      Interrupted zip operation since ingest was aborted")
                break
            }
            let newURL = dirURL.appendingPathComponent(file)
            var directory: ObjCBool = false
            if fm.fileExists(atPath: newURL.path, isDirectory: &directory) {
                if directory.boolValue {
                    var newChain = chain
                    newChain.append(file)
                    try appendDirectory(baseURL, chain: newChain, archive: archive, fm: fm)
                } else {
                    log("      Compressing \(newURL.path)")
                    let path = joinedChain + "/" + file
                    try archive.addEntry(with: path, relativeTo: baseURL)
                }
            }
        }
    }

    private func handleFileUrl(_ item: URL, _ data: Data, _ storeBytes: Bool) async throws {
        if PersistedOptions.readAndStoreFinderTagsAsLabels {
            let resourceValues = try? item.resourceValues(forKeys: [.tagNamesKey])
            contributedLabels = resourceValues?.tagNames
        } else {
            contributedLabels = nil
        }

        accessoryTitle = item.lastPathComponent
        let fm = FileManager.default
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: item.path, isDirectory: &directory) else {
            if storeBytes {
                setBytes(data)
            }
            representedClass = .url
            log("      received local file url for non-existent file: \(item.absoluteString)")
            await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
            return
        }

        if directory.boolValue {
            do {
                typeIdentifier = UTType.zip.identifier
                await setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)
                representedClass = .data
                let tempURL = Model.temporaryDirectoryUrl.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
                let a = Archive(url: tempURL, accessMode: .create)!
                let dirName = item.lastPathComponent
                let item = item.deletingLastPathComponent()
                try appendDirectory(item, chain: [dirName], archive: a, fm: fm)
                if flags.contains(.loadingAborted) {
                    log("      Cancelled zip operation since ingest was aborted")
                    return
                }
                try fm.moveAndReplaceItem(at: tempURL, to: bytesPath)
                log("      zipped files at url: \(item.absoluteString)")
            } catch {
                if storeBytes {
                    setBytes(data)
                }
                representedClass = .url
                log("      could not read data from file (\(error.localizedDescription)) treating as local file url: \(item.absoluteString)")
                await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
            }

        } else {
            let ext = item.pathExtension
            if !ext.isEmpty, let uti = UTType(filenameExtension: ext) {
                typeIdentifier = uti.identifier
            } else {
                typeIdentifier = UTType.data.identifier
            }
            representedClass = .data
            log("      read data from file url: \(item.absoluteString) - type assumed to be \(typeIdentifier)")
            let data = Data.forceMemoryMapped(contentsOf: item) ?? emptyData
            try await handleData(data, resolveUrls: false, storeBytes: storeBytes)
        }
    }

    func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool) async throws {
        setTitle(from: url)

        if url.isFileURL {
            try await handleFileUrl(url, data, storeBytes)

        } else {
            if storeBytes {
                setBytes(data)
            }
            representedClass = .url
            try await handleRemoteUrl(url, data, storeBytes)
        }
    }

    func removeIntents() {}

    func tryOpen(from viewController: NSViewController) {
        let shareItem = objectForShare

        if let shareItem = shareItem as? MKMapItem {
            shareItem.openInMaps(launchOptions: [:])

        } else if let contact = shareItem as? CNContact {
            let c = CNContactViewController(nibName: nil, bundle: nil)
            c.contact = contact
            viewController.presentAsModalWindow(c)

        } else if let item = shareItem as? URL {
            if !NSWorkspace.shared.open(item) {
                let message: String
                if item.isFileURL {
                    message = "macOS does not recognise the type of this file"
                } else {
                    message = "macOS does not recognise the type of this link"
                }
                Task {
                    await genericAlert(title: "Can't Open", message: message)
                }
            }
        } else {
            let previewPath = previewTempPath
            let fm = FileManager.default
            if fm.fileExists(atPath: previewPath.path) {
                try? fm.removeItem(at: previewPath)
            }
            try? fm.linkItem(at: bytesPath, to: previewPath)
            let now = Date()
            try? (previewPath as NSURL).setResourceValues([.contentAccessDateKey: now, .contentModificationDateKey: now]) // so the file is kept around in the temp directory for an hour
            fm.setDateAttribute(Component.lastModificationKey, at: previewPath, to: now)
            NSWorkspace.shared.open(previewPath)
        }
    }

    func add(to pasteboardItem: NSPasteboardItem) {
        guard hasBytes else { return }

        if let s = encodedUrl?.absoluteString {
            let tid = NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier)
            pasteboardItem.setString(s, forType: tid)

        } else if classWasWrapped, typeConforms(to: .plainText), isPlist, let s = decode() as? String {
            let tid = NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier)
            pasteboardItem.setString(s, forType: tid)

        } else {
            let tid = NSPasteboard.PasteboardType(typeIdentifier)
            pasteboardItem.setData(bytes ?? emptyData, forType: tid)
        }
    }

    @MainActor
    func pasteboardItem(forDrag: Bool) -> NSPasteboardWriting {
        if forDrag {
            return GladysFilePromiseProvider.provider(for: self, with: oneTitle, extraItems: [self], tags: parent?.labels)
        } else {
            let pi = NSPasteboardItem()
            add(to: pi)
            return pi
        }
    }

    @MainActor
    var quickLookItem: PreviewItem {
        PreviewItem(typeItem: self)
    }

    @MainActor
    var canPreview: Bool {
        if let canPreviewCache {
            return canPreviewCache
        }
        let res = fileExtension != nil && !(parent?.flags.contains(.needsUnlock) ?? true)
        canPreviewCache = res
        return res
    }

    func scanForBlobChanges() -> Bool {
        var detectedChange = false
        dataAccessQueue.sync(flags: .barrier) {
            let recordLocation = bytesPath
            let fm = FileManager.default
            guard fm.fileExists(atPath: recordLocation.path) else { return }

            if let fileModification = Model.unsafeModificationDate(for: recordLocation) {
                if let recordedModification = lastGladysBlobUpdate { // we've already stamped this
                    if recordedModification < fileModification { // is the file modified after we stamped it?
                        lastGladysBlobUpdate = fileModification
                        detectedChange = true
                    }
                } else {
                    lastGladysBlobUpdate = fileModification // have modification date but no stamp
                }
            } else {
                let now = Date()
                try? fm.setAttributes([FileAttributeKey.modificationDate: now], ofItemAtPath: recordLocation.path)
                lastGladysBlobUpdate = now // no modification date, no stamp
            }
        }
        return detectedChange
    }

    private static let lastModificationKey = "build.bru.Gladys.lastGladysModification"
    var lastGladysBlobUpdate: Date? { // be sure to protect with dataAccessQueue
        get {
            FileManager.default.getDateAttribute(Component.lastModificationKey, from: bytesPath)
        }
        set {
            FileManager.default.setDateAttribute(Component.lastModificationKey, at: bytesPath, to: newValue)
        }
    }

    var itemProviderForSharing: NSItemProvider {
        let p = NSItemProvider()
        registerForSharing(with: p)
        return p
    }

    func registerForSharing(with provider: NSItemProvider) {
        if let w = objectForShare as? NSItemProviderWriting {
            provider.registerObject(w, visibility: .all)
        } else {
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
                let p = Progress(totalUnitCount: 1)
                Task { @MainActor in
                    let response = self.dataForDropping ?? self.bytes
                    p.completedUnitCount = 1
                    completion(response, nil)
                }
                return p
            }
        }
    }
}
