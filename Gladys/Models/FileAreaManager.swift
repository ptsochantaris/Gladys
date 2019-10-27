import Foundation

final class FileAreaManager {
    static func mirrorBlobsToFiles() {
        let drops = Model.drops.filter { $0.goodToSave }
        BackgroundTask.registerForBackground()
        dataAccessQueue.async {
            do {
                let f = FileManager.default
                let baseDir = f.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
                if !f.fileExists(atPath: baseDir.path) {
                    try f.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
                }
                let createdUrls = try drops.compactMap { try $0.mirrorBlobToFiles(using: f, at: baseDir)?.path }
                try f.contentsOfDirectory(atPath: baseDir.path).compactMap { name -> String? in
                    let existing = baseDir.appendingPathComponent(name).path
                    return createdUrls.contains(existing) ? nil : existing
                }.forEach {
                    try f.removeItem(atPath: $0)
                }
            } catch {
                log("Error while mirroring items from file area: \(error.localizedDescription)")
            }
            BackgroundTask.unregisterForBackground()
        }
    }
}

extension ArchivedDropItem {
    fileprivate func mirrorBlobToFiles(using f: FileManager, at baseDir: URL) throws -> URL? {
        let url = baseDir.appendingPathComponent(displayTitleOrUuid.dropFilenameSafe.truncate(limit: 32))
        if typeItems.count == 1, let child = typeItems.first {
            return try child.mirror(to: url, asChild: false, using: f)
        } else {
            try mirror(to: url, using: f)
            return url
        }
    }
    
    private func mirror(to url: URL, using f: FileManager) throws {
        let path = url.path
        if f.fileExists(atPath: path) {
            if let date = try f.attributesOfItem(atPath: url.path)[FileAttributeKey.modificationDate] as? Date, date == updatedAt {
                return
            } else {
                try f.removeItem(atPath: path)
            }
        }
        try f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        try f.setAttributes([
            .extensionHidden: false,
            .creationDate: createdAt,
            .modificationDate: updatedAt
        ], ofItemAtPath: path)
        for child in typeItems {
            _ = try child.mirror(to: url, asChild: true, using: f)
        }
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
            if let date = try f.attributesOfItem(atPath: url.path)[FileAttributeKey.modificationDate] as? Date, date == updatedAt {
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
        
        return url
    }
}
