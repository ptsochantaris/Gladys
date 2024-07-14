import Contacts
import Foundation
import MapKit
#if canImport(UIKit)
    import QuickLook
#endif
import GladysCommon

public extension Component {
    var sizeDescription: String? {
        diskSizeFormatter.string(fromByteCount: sizeInBytes)
    }

    var canPreview: Bool {
        if let cachedEntry = canPreviewCache[uuid] {
            return cachedEntry
        }
        #if canImport(AppKit)
            let res = fileExtension != nil && !(parent?.flags.contains(.needsUnlock) ?? true)
        #else
            let res = isWebArchive || QLPreviewController.canPreview(PreviewItem(typeItem: self))
        #endif
        canPreviewCache[uuid] = res
        return res
    }

    func deleteFromStorage() async {
        await CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
        let fm = FileManager.default
        if fm.fileExists(atPath: folderUrl.path) {
            log("Removing component storage at: \(folderUrl.path)")
            try? fm.removeItem(at: folderUrl)
        }
        clearCacheData(for: uuid)
    }

    var objectForShare: Any? {
        if typeIdentifier == "com.apple.mapkit.map-item", let item = decode() as? MKMapItem {
            return item
        }

        if typeConforms(to: .vCard), let bytes, let contact = (try? CNContactVCardSerialization.contacts(with: bytes))?.first {
            return contact
        }

        if let url = encodedUrl {
            return url
        }

        return decode()
    }

    func replaceURL(_ newUrl: URL) {
        guard isURL else { return }

        let decoded = decode()
        if decoded is URL {
            let data = try? PropertyListSerialization.data(fromPropertyList: newUrl, format: .binary, options: 0)
            setBytes(data)
        } else if let array = decoded as? NSArray {
            let newArray = array.map { (item: Any) -> Any in
                if let text = item as? String, let url = URL(string: text), let scheme = url.scheme, scheme.isPopulated {
                    newUrl.absoluteString
                } else {
                    item
                }
            }
            let data = try? PropertyListSerialization.data(fromPropertyList: newArray, format: .binary, options: 0)
            setBytes(data)
        } else {
            let data = Data(newUrl.absoluteString.utf8)
            setBytes(data)
        }
        encodedURLCache[uuid] = (true, newUrl)
        setTitle(from: newUrl as URL)
        markComponentUpdated()
    }

    func prepareFilename(name: String, directory: String?) -> String {
        var name = name

        if let ext = fileExtension {
            if ext == "jpeg", name.hasSuffix(".jpg") {
                name = String(name.dropLast(4))

            } else if ext == "mpeg", name.hasSuffix(".mpg") {
                name = String(name.dropLast(4))

            } else if ext == "html", name.hasSuffix(".htm") {
                name = String(name.dropLast(4))

            } else if name.hasSuffix("." + ext) {
                name = String(name.dropLast(ext.count + 1))
            }

            name = name.truncate(limit: 255 - (ext.count + 1)) + "." + ext
        } else {
            name = name.truncate(limit: 255)
        }

        if let directory {
            name = directory.truncate(limit: 255) + "/" + name
        }

        // for now, remove in a few weeks
        return name.replacingOccurrences(of: "\0", with: "")
    }
}
