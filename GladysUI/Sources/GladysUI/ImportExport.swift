import Foundation
import GladysCommon
import ZIPFoundation

public enum ImportExport {
    private class FileManagerFilter: NSObject, FileManagerDelegate {
        func fileManager(_: FileManager, shouldCopyItemAt srcURL: URL, to _: URL) -> Bool {
            guard let lastComponent = srcURL.pathComponents.last else { return false }
            return !(lastComponent == "shared-blob" || lastComponent == "ck-record" || lastComponent == "ck-share")
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @MainActor
    public static func createArchive(using filter: Filter, progress: Progress) async throws -> URL {
        let eligibleItems = filter.eligibleDropsForExport.filter { !$0.isImportedShare }
        let count = 2 + eligibleItems.count

        let p = Progress(totalUnitCount: Int64(count))
        progress.addChild(p, withPendingUnitCount: 100)

        return try await createArchiveThread(progress: p, eligibleItems: eligibleItems)
    }

    @concurrent private static func createArchiveThread(progress p: Progress, eligibleItems: [ArchivedItem]) async throws -> URL {
        let fm = FileManager()
        let tempPath = temporaryDirectoryUrl.appendingPathComponent("Gladys Archive.gladysArchive")
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
            let sourceForItem = appStorageUrl.appendingPathComponent(uuidString)
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

    public static func createZip(using filter: Filter, progress: Progress) async throws -> URL {
        let dropsCopy = await filter.eligibleDropsForExport
        let itemCount = Int64(1 + dropsCopy.count)

        let p = Progress(totalUnitCount: itemCount)
        progress.addChild(p, withPendingUnitCount: 100)

        return try await createZipThread(dropsCopy: dropsCopy, progress: p)
    }

    @concurrent private static func createZipThread(dropsCopy: ContiguousArray<ArchivedItem>, progress p: Progress) async throws -> URL {
        let tempPath = temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

        let fm = FileManager.default
        let path = tempPath.path
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }

        p.completedUnitCount += 1

        guard let archive = try? Archive(url: tempPath, accessMode: .create, pathEncoding: nil) else {
            throw GladysError.creatingArchiveFailed
        }

        for item in dropsCopy {
            let dir = await item.displayTitleOrUuid.filenameSafe

            let components = await item.components
            if components.count == 1, let typeItem = components.first {
                try await addZipItem(typeItem, directory: nil, name: dir, in: archive)

            } else {
                for typeItem in components {
                    try await addZipItem(typeItem, directory: dir, name: typeItem.typeDescription, in: archive)
                }
            }
            p.completedUnitCount += 1
        }

        return tempPath
    }

    @concurrent private static func addZipItem(_ typeItem: Component, directory: String?, name: String, in archive: Archive) async throws {
        var bytes: Data?
        if await typeItem.isWebURL, let url = await typeItem.encodedUrl {
            bytes = url.urlFileContent

        } else if await typeItem.classWasWrapped {
            bytes = await typeItem.dataForDropping
        }

        let B: Data? = if let bytes {
            bytes
        } else {
            await typeItem.bytes
        }

        guard let B else { return }

        let timmedName = await typeItem.prepareFilename(name: name, directory: directory)
        let provider: Provider = { (pos: Int64, size: Int) throws -> Data in
            B[pos ..< pos + Int64(size)]
        }
        try archive.addEntry(with: timmedName, type: .file, uncompressedSize: Int64(B.count), provider: provider)
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @concurrent private static func bringInItem(_ item: ArchivedItem, from url: URL, moveItem: Bool) async throws -> Bool {
        let remotePath = url.appendingPathComponent(item.uuid.uuidString)
        let fm = FileManager.default
        if !fm.fileExists(atPath: remotePath.path) {
            log("Warning: Item \(item.uuid) declared but not found on imported archive, skipped")
            return false
        }

        let folderUrl = await item.folderUrl
        if moveItem {
            try fm.moveAndReplaceItem(at: remotePath, to: folderUrl)
        } else {
            try fm.copyAndReplaceItem(at: remotePath, to: folderUrl)
        }

        await item.setStatus(.needsIngest)
        await item.markUpdated()
        await item.removeFromCloudkit()

        return true
    }

    @concurrent public static func importArchive(from url: URL, removingOriginal: Bool) async throws {
        let fm = FileManager.default
        defer {
            if removingOriginal {
                try? fm.removeItem(at: url)
            }
            Task {
                await Model.save()
            }
        }

        let finalPath = url.appendingPathComponent("items.json")
        guard let data = Data.forceMemoryMapped(contentsOf: finalPath) else {
            throw GladysError.importingArchiveFailed
        }
        let itemsInPackage = try loadDecoder.decode([ArchivedItem].self, from: data)

        for item in itemsInPackage.reversed() {
            if let i = await DropStore.indexOfItem(with: item.uuid) {
                let item = await DropStore.allDrops[i]
                if await item.updatedAt >= item.updatedAt {
                    continue
                }
                if await item.shareMode != .none {
                    continue
                }
                if try await bringInItem(item, from: url, moveItem: removingOriginal) {
                    await DropStore.replace(drop: item, at: i)
                }
            } else {
                if try await bringInItem(item, from: url, moveItem: removingOriginal) {
                    await DropStore.insert(drop: item, at: 0)
                }
            }
        }
    }
}
