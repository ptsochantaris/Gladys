import Foundation

final class MirrorManager {
    
    static fileprivate let mirrorUuidKey = "build.bru.Gladys.fileMirrorUuidKey"
    
    private static let mirrorQueue: OperationQueue = {
        let o = OperationQueue()
        o.maxConcurrentOperationCount = 1
        return o
    }()
    
    static var mirrorBase: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
    }
    
    private static func coordinateWrite(types: [NSFileCoordinator.WritingOptions], perform: @escaping ()->Void) {
        let coordinator = NSFileCoordinator(filePresenter: monitor)
        let intents = types.map { NSFileAccessIntent.writingIntent(with: mirrorBase, options: $0) }
        coordinator.coordinate(with: intents, queue: mirrorQueue) { error in
            if let error = error {
                log("Error while trying to coordinate mirror: \(error.localizedDescription)")
                return
            }
            perform()
        }
    }
    
    private static func coordinateRead(type: NSFileCoordinator.ReadingOptions, perform: @escaping ()->Void) {
        let coordinator = NSFileCoordinator(filePresenter: monitor)
        coordinator.coordinate(with: [.readingIntent(with: mirrorBase, options: type)], queue: mirrorQueue) { error in
            if let error = error {
                log("Error while trying to coordinate mirror: \(error.localizedDescription)")
                return
            }
            perform()
        }
    }
    
    static func removeMirrorIfNeeded(completion: @escaping ()->Void) {
        let baseDir = mirrorBase
        coordinateWrite(types: [.forDeleting]) {
            let f = FileManager.default
            if f.fileExists(atPath: baseDir.path) {
                try? f.removeItem(at: baseDir)
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    static func removeItems(items: [ArchivedDropItem]) {
        let paths = items.map { $0.fileMirrorPath }
        coordinateWrite(types: [.forDeleting]) {
            let f = FileManager.default
            for path in paths {
                if f.fileExists(atPath: path) {
                    try? f.removeItem(atPath: path)
                }
            }
        }
    }
            
    private static var monitor: FileMonitor?
    
    static func startMirrorMonitoring() {
        if monitor == nil {
            monitor = FileMonitor(directory: mirrorBase) { url in
                self.handleChange(at: url)
            }
        }
    }
    
    private static func handleChange(at url: URL) {
        coordinateRead(type: []) {
            if let uuid = FileManager.default.getUUIDAttribute(MirrorManager.mirrorUuidKey, from: url) {
                if let item = Model.item(uuid: uuid), item.shouldAssimilateFromMirror {
                    item.assimilateMirrorChanges()
                } else if let typeItem = Model.typeItem(uuid: uuid.uuidString), let parent = typeItem.parent, parent.shouldAssimilateFromMirror {
                    parent.assimilateMirrorChanges()
                }
            }
        }
    }
    
    static func scanForMirrorChanges(items: [ArchivedDropItem], completion: @escaping ()->Void) {
        coordinateRead(type: []) {
            items.filter { $0.shouldAssimilateFromMirror }.forEach {
                $0.assimilateMirrorChanges()
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    static func stopMirrorMonitoring() {
        if let m = monitor {
            m.stop()
            monitor = nil
        }
    }

    static func mirrorToFiles(from drops: [ArchivedDropItem], completion: @escaping ()->Void) {
        coordinateWrite(types: [.forDeleting, .forMerging]) {

            let start = Date()
            let baseDir = mirrorBase
            let f = FileManager.default
            
            do {
                try _pruneMirror(keeping: drops, at: baseDir, using: f)
            } catch {
                log("Error while pruning mirror: \(error.localizedDescription)")
            }

            log("Pruning done \(-start.timeIntervalSinceNow)s")

            do {
                let dropsToMirror = drops.filter { !$0.skipMirrorAtNextSave }
                try _mirrorToFiles(from: dropsToMirror, at: baseDir, using: f)
            } catch {
                log("Error while mirroring: \(error.localizedDescription)")
            }
            
            log("Mirroring done \(-start.timeIntervalSinceNow)s")

            DispatchQueue.main.async {
                drops.filter { $0.skipMirrorAtNextSave }.forEach { $0.skipMirrorAtNextSave = false }
                completion()
            }
        }
    }
    
    static private func _pruneMirror(keeping drops: [ArchivedDropItem], at baseDir: URL, using f: FileManager) throws {
        let urlsOfExistingItems = drops.map { $0.fileMirrorPath }
        try f.contentsOfDirectory(atPath: baseDir.path).compactMap { name -> String? in
            let existing = baseDir.appendingPathComponent(name).path
            return urlsOfExistingItems.contains(existing)
                ? nil
                : existing
        }.forEach {
            log("Pruning \($0)")
            try f.removeItem(atPath: $0)
        }
    }

    static private func _mirrorToFiles(from drops: [ArchivedDropItem], at baseDir: URL, using f: FileManager) throws {
        if !f.fileExists(atPath: baseDir.path) {
            log("Creating mirror directory \(baseDir.path)")
            try f.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
        }

        if drops.isEmpty {
            log("Nothing to mirror")
            return
        }
        
        try drops.forEach { try $0.mirrorToFiles(using: f) }
    }
        
    fileprivate static func modificationDate(for url: URL, using f: FileManager) throws -> Date? {
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

extension ArchivedDropItem {
    fileprivate var directoryMirrorUrl: URL {
        return MirrorManager.mirrorBase.appendingPathComponent(displayTitleOrUuid.dropFilenameSafe.truncate(limit: 32))
    }
    
    fileprivate var fileMirrorPath: String {
        if typeItems.count == 1 {
            return typeItems.first!.typeMirrorUrl.path
        }
        return directoryMirrorUrl.path
    }
    
    fileprivate func mirrorToFiles(using f: FileManager) throws {
        if typeItems.count == 0 {
            return
        } else if typeItems.count == 1 {
            _ = try typeItems.first!.mirror(using: f)
        } else {
            try mirror(to: directoryMirrorUrl, using: f)
        }
    }
    
    private func mirror(to url: URL, using f: FileManager) throws {
        
        let path = url.path
        if f.fileExists(atPath: path) {
            if let fileUuid = f.getUUIDAttribute(MirrorManager.mirrorUuidKey, from: url) {
                if uuid != fileUuid {
                    return // same name but other object
                }
            }
        } else {
            try f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        
        var mirrored = false
        for child in typeItems {
            if try child.mirror(using: f) {
                mirrored = true
            }
        }
        
        if mirrored {
            f.setUUIDAttribute(MirrorManager.mirrorUuidKey, at: url, to: uuid)
            log("Mirrored item dir \(uuid.uuidString)")
        }
    }
    
    fileprivate var shouldAssimilateFromMirror: Bool {
        if needsSaving || isTransferring || isDeleting || needsReIngest {
            return false
        }
        return typeItems.contains { $0.shouldAssimilateFromMirror }
    }
    
    fileprivate func assimilateMirrorChanges() {

        typeItems.forEach {
            log("Assimilating mirror changes into component \($0.uuid.uuidString)")
            try? FileManager.default.copyAndReplaceItem(at: $0.typeMirrorUrl, to: $0.bytesPath)
            $0.markUpdated()
        }
        markUpdated()
        needsReIngest = true
        skipMirrorAtNextSave = true
                
        DispatchQueue.main.async {
            self.reIngest(delegate: ViewController.shared)
        }
    }
}

extension ArchivedDropItemType {
    fileprivate var typeMirrorUrl: URL {
        guard let parent = parent else {
            abort()
        }
        
        var url = parent.directoryMirrorUrl
        
        if parent.typeItems.count != 1 {
            url.appendPathComponent(filenameTypeIdentifier)
        }
    
        if let ext = fileExtension, !url.path.hasSuffix("." + ext) {
            url = url.appendingPathExtension(ext)
        }
        
        return url
    }
    
    fileprivate func mirror(using f: FileManager) throws -> Bool {
                
        if !f.fileExists(atPath: bytesPath.path) {
            return false
        }
        
        var url = typeMirrorUrl

        let path = url.path
        if f.fileExists(atPath: path) {
            
            if let fileUuid = f.getUUIDAttribute(MirrorManager.mirrorUuidKey, from: url) {
                if uuid != fileUuid {
                    return false // same name but was written by identically named object
                }
            }
            
            if let fileDate = try? MirrorManager.modificationDate(for: url, using: f), fileDate == updatedAt {
                return false
            } else {
                try f.removeItem(atPath: path)
            }
        }
                
        try f.copyItem(at: bytesPath, to: url)
        
        f.setUUIDAttribute(MirrorManager.mirrorUuidKey, at: url, to: uuid)

        var v = URLResourceValues()
        v.hasHiddenExtension = true
        v.creationDate = createdAt
        v.contentModificationDate = updatedAt
        //v.typeIdentifier = typeIdentifier
        try url.setResourceValues(v)
                
        log("Mirrored component \(uuid.uuidString) to \(url.path)")
        return true
    }
    
    fileprivate var shouldAssimilateFromMirror: Bool {
        let f = FileManager.default
        let url = typeMirrorUrl
        let path = url.path
        
        guard f.fileExists(atPath: path) else {
            return false
        }

        if let fileDate = try? MirrorManager.modificationDate(for: url, using: f), fileDate > updatedAt {
            return true
        }
        
        return false
    }
}
