import Foundation

final class FileAreaManager {
    
    static fileprivate let mirrorDateKey = "build.bru.Gladys.fileMirrorDateKey"
    static fileprivate let mirrorUuidKey = "build.bru.Gladys.fileMirrorUuidKey"

    static let fileAreaQueue = DispatchQueue(label: "build.bru.Gladys.mirrorQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

    static func mirrorToFiles(from drops: [ArchivedDropItem]) {
        if drops.isEmpty {
            log("Nothing to mirror")
            return
        }
        BackgroundTask.registerForBackground()
        fileAreaQueue.async {
            log("Mirroring \(drops.count) items...")
            do {
                let f = FileManager.default
                let baseDir = f.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
                if !f.fileExists(atPath: baseDir.path) {
                    try f.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
                }
                let createdUrls = try drops.compactMap { try $0.mirrorToFiles(using: f, at: baseDir)?.path }
                log("Removing files for non-existent items...")
                try f.contentsOfDirectory(atPath: baseDir.path).compactMap { name -> String? in
                    let existing = baseDir.appendingPathComponent(name).path
                    return createdUrls.contains(existing) ? nil : existing
                }.forEach {
                    try f.removeItem(atPath: $0)
                }
            } catch {
                log("Error while mirroring items from file area: \(error.localizedDescription)")
            }
            log("Mirroring items done")
            BackgroundTask.unregisterForBackground()
        }
    }
}

extension ArchivedDropItem {
    fileprivate func mirrorToFiles(using f: FileManager, at baseDir: URL) throws -> URL? {
        try dataAccessQueue.sync {
            let url = baseDir.appendingPathComponent(displayTitleOrUuid.dropFilenameSafe.truncate(limit: 32))
            if typeItems.count == 1, let child = typeItems.first {
                return try child.mirror(to: url, asChild: false, using: f)
            } else {
                try mirror(to: url, using: f)
                return url
            }
        }
    }
    
    private func mirror(to url: URL, using f: FileManager) throws {
        let path = url.path
        if f.fileExists(atPath: path) {
            if let fileUuid = f.getUUIDAttribute(FileAreaManager.mirrorUuidKey, from: url) {
                if uuid != fileUuid {
                    return // same name but other object
                }
            }
            
            if let date = f.getDateAttribute(FileAreaManager.mirrorDateKey, from: url), date.timeIntervalSinceReferenceDate.rounded() == updatedAt.timeIntervalSinceReferenceDate.rounded() {
                return
            } else {
                try f.removeItem(atPath: path)
            }
        }
        
        try f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        f.setDateAttribute(FileAreaManager.mirrorDateKey, at: url, to: updatedAt)
        f.setUUIDAttribute(FileAreaManager.mirrorUuidKey, at: url, to: uuid)
        try f.setAttributes([
            .extensionHidden: false,
            .creationDate: createdAt,
            .modificationDate: updatedAt,
        ], ofItemAtPath: path)
        for child in typeItems {
            _ = try child.mirror(to: url, asChild: true, using: f)
        }
        log("Mirrored item dir \(uuid.uuidString)")
    }
}

extension ArchivedDropItemType {
    fileprivate func mirror(to parentUrl: URL, asChild: Bool, using f: FileManager) throws -> URL {
        if !f.fileExists(atPath: bytesPath.path) {
            return parentUrl
        }

        var url = asChild ? parentUrl.appendingPathComponent(filenameTypeIdentifier) : parentUrl
        
        if let ext = fileExtension, !url.path.hasSuffix("." + ext) {
            url = url.appendingPathExtension(ext)
        }
        
        let path = url.path
        if f.fileExists(atPath: path) {
            
            if let fileUuid = f.getUUIDAttribute(FileAreaManager.mirrorUuidKey, from: url) {
                if uuid != fileUuid {
                    return url // same name but other object
                }
            }
            
            if let date = f.getDateAttribute(FileAreaManager.mirrorDateKey, from: url), date.timeIntervalSinceReferenceDate.rounded() == updatedAt.timeIntervalSinceReferenceDate.rounded() {
                return url
            } else {
                try f.removeItem(atPath: path)
            }
        }
        
        try f.copyItem(at: bytesPath, to: url)
        try f.setAttributes([
            .extensionHidden: false,
            .creationDate: createdAt,
            .modificationDate: updatedAt,
            .type: typeIdentifier
        ], ofItemAtPath: path)
        f.setDateAttribute(FileAreaManager.mirrorDateKey, at: url, to: updatedAt)
        f.setUUIDAttribute(FileAreaManager.mirrorUuidKey, at: url, to: uuid)

        log("Mirrored component \(uuid.uuidString)")
        return url
    }
}
