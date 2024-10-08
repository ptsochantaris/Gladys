import Contacts
import ContactsUI
import GladysAppKit
import GladysCommon
import GladysUI
import MapKit
import UniformTypeIdentifiers

extension Component {
    var isArchivable: Bool {
        if let e = encodedUrl, !e.isFileURL, e.host != nil, let s = e.scheme, s.hasPrefix("http") {
            true
        } else {
            false
        }
    }

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
                let message = if item.isFileURL {
                    "macOS does not recognise the type of this file"
                } else {
                    "macOS does not recognise the type of this link"
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
            pasteboardItem.setData(bytes ?? Data(), forType: tid)
        }
    }

    func pasteboardItem(forDrag: Bool) -> NSPasteboardWriting {
        if forDrag {
            return GladysFilePromiseProvider.provider(for: self, with: oneTitle, extraItems: [self], tags: parent?.labels)
        } else {
            let pi = NSPasteboardItem()
            add(to: pi)
            return pi
        }
    }

    var quickLookItem: PreviewItem {
        PreviewItem(typeItem: self)
    }

    func scanForBlobChanges() -> Bool {
        let recordLocation = bytesPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: recordLocation.path) else { return false }

        if let fileModification = Model.unsafeModificationDate(for: recordLocation) {
            if let recordedModification = lastGladysBlobUpdate { // we've already stamped this
                if recordedModification < fileModification { // is the file modified after we stamped it?
                    lastGladysBlobUpdate = fileModification
                    return true
                }
            } else {
                lastGladysBlobUpdate = fileModification // have modification date but no stamp
            }
        } else {
            let now = Date()
            try? fm.setAttributes([FileAttributeKey.modificationDate: now], ofItemAtPath: recordLocation.path)
            lastGladysBlobUpdate = now // no modification date, no stamp
        }
        return false
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
                Task {
                    let response = await MainActor.run { self.dataForDropping ?? self.bytes }
                    p.completedUnitCount = 1
                    completion(response, nil)
                }
                return p
            }
        }
    }
}
