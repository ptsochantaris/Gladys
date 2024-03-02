import Foundation
import GladysCommon
import ZIPFoundation

@MainActor
public final class ImportExport {
    public init() {}

    private class FileManagerFilter: NSObject, FileManagerDelegate {
        func fileManager(_: FileManager, shouldCopyItemAt srcURL: URL, to _: URL) -> Bool {
            guard let lastComponent = srcURL.pathComponents.last else { return false }
            return !(lastComponent == "shared-blob" || lastComponent == "ck-record" || lastComponent == "ck-share")
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    @discardableResult
    public func createArchive(using filter: Filter, completion: @escaping (Result<URL, Error>) -> Void) -> Progress {
        let eligibleItems: ContiguousArray = filter.eligibleDropsForExport.filter { !$0.isImportedShare }
        let count = 2 + eligibleItems.count
        let p = Progress(totalUnitCount: Int64(count))

        Task.detached {
            do {
                let url = try self.createArchiveThread(progress: p, eligibleItems: eligibleItems)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }

        return p
    }

    private nonisolated func createArchiveThread(progress p: Progress, eligibleItems: ContiguousArray<ArchivedItem>) throws -> URL {
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

    @discardableResult
    public func createZip(using filter: Filter, completion: @escaping (Result<URL, Error>) -> Void) -> Progress {
        let dropsCopy = filter.eligibleDropsForExport
        let itemCount = Int64(1 + dropsCopy.count)
        let p = Progress(totalUnitCount: itemCount)

        Task.detached {
            do {
                let url = try await self.createZipThread(dropsCopy: dropsCopy, progress: p)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }

        return p
    }

    private nonisolated func createZipThread(dropsCopy: ContiguousArray<ArchivedItem>, progress p: Progress) async throws -> URL {
        let tempPath = temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

        let fm = FileManager.default
        let path = tempPath.path
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }

        p.completedUnitCount += 1

        guard let archive = try Archive(url: tempPath, accessMode: .create) else {
            throw GladysError.creatingArchiveFailed
        }

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

        return tempPath
    }

    private func addZipItem(_ typeItem: Component, directory: String?, name: String, in archive: Archive) async throws {
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

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    private func bringInItem(_ item: ArchivedItem, from url: URL, using fm: FileManager, moveItem: Bool) throws -> Bool {
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

        item.status = .needsIngest
        item.markUpdated()
        item.removeFromCloudkit()

        return true
    }

    public func importArchive(from url: URL, removingOriginal: Bool) throws {
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
            if let i = DropStore.indexOfItem(with: item.uuid) {
                if DropStore.allDrops[i].updatedAt >= item.updatedAt || DropStore.allDrops[i].shareMode != .none {
                    continue
                }
                if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    DropStore.replace(drop: item, at: i)
                }
            } else {
                if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    DropStore.insert(drop: item, at: 0)
                }
            }
        }
    }
}
