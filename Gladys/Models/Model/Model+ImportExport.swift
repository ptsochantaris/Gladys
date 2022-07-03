import Foundation
import ZIPFoundation

extension Model {
    private static func bringInItem(_ item: ArchivedItem, from url: URL, using fm: FileManager, moveItem: Bool) throws -> Bool {
        let remotePath = url.appendingPathComponent(item.uuid.uuidString)
        if !fm.fileExists(atPath: remotePath.path) {
            log("Warning: Item \(item.uuid) declared but not found on imported archive, skipped")
            return false
        }

        if moveItem {
            try fm.moveAndReplaceItem(at: remotePath, to: item.folderUrl)
        } else {
            try fm.copyAndReplaceItem(at: remotePath, to: item.folderUrl)
        }

        item.needsReIngest = true
        item.markUpdated()
        item.removeFromCloudkit()

        return true
    }

    static func importArchive(from url: URL, removingOriginal: Bool) throws {
        let fm = FileManager.default
        defer {
            if removingOriginal {
                try? fm.removeItem(at: url)
            }
            save()
        }

        let finalPath = url.appendingPathComponent("items.json")
        guard let data = Data.forceMemoryMapped(contentsOf: finalPath) else {
            throw GladysError.importingArchiveFailed.error
        }
        let itemsInPackage = try loadDecoder.decode([ArchivedItem].self, from: data)

        for item in itemsInPackage.reversed() {
            if let i = firstIndexOfItem(with: item.uuid) {
                if drops[i].updatedAt >= item.updatedAt || drops[i].shareMode != .none {
                    continue
                }
                if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    drops[i] = item
                }
            } else {
                if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    drops.insert(item, at: 0)
                }
            }
        }
    }

    private class FileManagerFilter: NSObject, FileManagerDelegate {
        func fileManager(_: FileManager, shouldCopyItemAt srcURL: URL, to _: URL) -> Bool {
            guard let lastComponent = srcURL.pathComponents.last else { return false }
            return !(lastComponent == "shared-blob" || lastComponent == "ck-record" || lastComponent == "ck-share")
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @discardableResult
    static func createArchive(using filter: Filter, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        let eligibleItems: ContiguousArray = filter.eligibleDropsForExport.filter { !$0.isImportedShare }
        let count = 2 + eligibleItems.count
        let p = Progress(totalUnitCount: Int64(count))

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try createArchiveThread(progress: p, eligibleItems: eligibleItems)
                completion(url, nil)
            } catch {
                completion(nil, error)
            }
        }

        return p
    }

    private static func createArchiveThread(progress p: Progress, eligibleItems: ContiguousArray<ArchivedItem>) throws -> URL {
        let fm = FileManager()
        let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys Archive.gladysArchive")
        let path = tempPath.path
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }

        let delegate = FileManagerFilter()
        fm.delegate = delegate

        p.completedUnitCount += 1

        try fm.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)
        for item in eligibleItems {
            let uuidString = item.uuid.uuidString
            let sourceForItem = Model.appStorageUrl.appendingPathComponent(uuidString)
            let destinationForItem = tempPath.appendingPathComponent(uuidString)
            try fm.copyAndReplaceItem(at: sourceForItem, to: destinationForItem)
            p.completedUnitCount += 1
        }

        let data = try saveEncoder.encode(eligibleItems)
        let finalPath = tempPath.appendingPathComponent("items.json")
        try data.write(to: finalPath)
        p.completedUnitCount += 1

        return tempPath
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @discardableResult
    static func createZip(using filter: Filter, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        let dropsCopy = filter.eligibleDropsForExport
        let itemCount = Int64(1 + dropsCopy.count)
        let p = Progress(totalUnitCount: itemCount)

        Task.detached {
            do {
                let url = try await createZipThread(dropsCopy: dropsCopy, progress: p)
                completion(url, nil)
            } catch {
                completion(nil, error)
            }
        }

        return p
    }

    static func createZipThread(dropsCopy: ContiguousArray<ArchivedItem>, progress p: Progress) async throws -> URL {
        let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

        let fm = FileManager.default
        let path = tempPath.path
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }

        p.completedUnitCount += 1

        if let archive = Archive(url: tempPath, accessMode: .create) {
            for item in dropsCopy {
                let dir = item.displayTitleOrUuid.filenameSafe

                if item.components.count == 1, let typeItem = item.components.first {
                    try await addZipItem(typeItem, directory: nil, name: dir, in: archive)

                } else {
                    for typeItem in item.components {
                        try await addZipItem(typeItem, directory: dir, name: typeItem.typeDescription, in: archive)
                    }
                }
                p.completedUnitCount += 1
            }
        }

        return tempPath
    }

    private static func addZipItem(_ typeItem: Component, directory: String?, name: String, in archive: Archive) async throws {
        var bytes: Data?
        if typeItem.isWebURL, let url = typeItem.encodedUrl {
            bytes = url.urlFileContent

        } else if typeItem.classWasWrapped {
            bytes = typeItem.dataForDropping ?? typeItem.bytes
        }
        if let B = bytes ?? typeItem.bytes {
            let timmedName = typeItem.prepareFilename(name: name, directory: directory)
            let provider: Provider = { (pos: Int64, size: Int) throws -> Data in
                B[pos ..< pos + Int64(size)]
            }
            try archive.addEntry(with: timmedName, type: .file, uncompressedSize: Int64(B.count), provider: provider)
        }
    }

    static func trimTemporaryDirectory() {
        do {
            let fm = FileManager.default
            let contents = try fm.contentsOfDirectory(atPath: temporaryDirectoryUrl.path)
            let now = Date()
            for name in contents {
                let url = temporaryDirectoryUrl.appendingPathComponent(name)
                let path = url.path
                if (Component.PreviewItem.previewUrls[url] ?? 0) > 0 {
                    log("Temporary directory entry is in use, will skip check: \(path)")
                    continue
                }
                let attributes = try fm.attributesOfItem(atPath: path)
                if let accessDate = (attributes[FileAttributeKey.modificationDate] ?? attributes[FileAttributeKey.creationDate]) as? Date, now.timeIntervalSince(accessDate) > 3600 {
                    log("Temporary directory entry is old, will trim: \(path)")
                    try? fm.removeItem(atPath: path)
                }
            }
        } catch {
            log("Error trimming temporary directory: \(error.localizedDescription)")
        }
    }
}
