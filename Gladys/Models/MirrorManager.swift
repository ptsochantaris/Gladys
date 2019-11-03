import Foundation

final class MirrorManager {
    
    static fileprivate let mirrorUuidKey = "build.bru.Gladys.fileMirrorUuidKey"
    
    private static let mirrorQueue: OperationQueue = {
        let o = OperationQueue()
        o.qualityOfService = .background
        o.maxConcurrentOperationCount = 1
        return o
    }()
    
    fileprivate static let mirrorBase: URL = {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
    }()
    
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
        coordinateWrite(types: [.forDeleting]) {
            log("Deleting file mirror")
            let f = FileManager.default
            if f.fileExists(atPath: mirrorBase.path) {
                try? f.removeItem(at: mirrorBase)
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
        mirrorQueue.addOperation {
            if monitor == nil {
                monitor = FileMonitor(directory: mirrorBase) { url in
                    handleChange(at: url)
                }
            }
        }
    }
        
    private static func handleChange(at url: URL) {
        coordinateRead(type: []) {
            if let uuid = FileManager.default.getUUIDAttribute(MirrorManager.mirrorUuidKey, from: url), let typeItem = Model.typeItem(uuid: uuid.uuidString) {
                typeItem.parent?.assimilateMirrorChanges()
            }
        }
    }
    
    static func scanForMirrorChanges(items: [ArchivedDropItem], completion: @escaping ()->Void) {
        coordinateRead(type: []) {
            for item in items {
                item.assimilateMirrorChanges()
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    static func stopMirrorMonitoring() {
        mirrorQueue.addOperation {
            if let m = monitor {
                m.stop()
                monitor = nil
            }
        }
    }
    
    static func mirrorToFiles(from drops: [ArchivedDropItem], andPruneOthers: Bool, completion: @escaping ()->Void) {
        coordinateWrite(types: [.forDeleting, .forMerging]) {
            
            do {
                let start = Date()
                let f = FileManager.default
                let baseDir = mirrorBase.path

                var pathsExamined = Set<String>()
                pathsExamined.reserveCapacity(drops.count)

                if !f.fileExists(atPath: baseDir) {
                    log("Creating mirror directory \(baseDir)")
                    try f.createDirectory(atPath: baseDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                for drop in drops {
                    if let examinedPath = try drop.mirrorToFiles(using: f, pathsExamined: pathsExamined) {
                        pathsExamined.insert(examinedPath)
                    }
                }

                if andPruneOthers {
                    let prefix = baseDir + "/"
                    try f.contentsOfDirectory(atPath: baseDir).forEach {
                        let p = prefix + $0
                        if !pathsExamined.contains(p) {
                            log("Pruning \(p)")
                            try f.removeItem(atPath: p)
                        }
                    }
                }

                log("Mirroring done \(-start.timeIntervalSinceNow)s")

            } catch {
                log("Error while mirroring: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                drops.filter { $0.skipMirrorAtNextSave }.forEach { $0.skipMirrorAtNextSave = false }
                completion()
            }
        }
    }
            
    fileprivate static func modificationDate(for url: URL, using f: FileManager) throws -> Date? {
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

extension ArchivedDropItem {
    fileprivate var fileMirrorPath: String {
        var base = MirrorManager.mirrorBase.appendingPathComponent(displayTitleOrUuid.dropFilenameSafe.truncate(limit: 32)).path
        if typeItems.count == 1, let item = typeItems.first {
            if let ext = item.fileExtension, !base.hasSuffix("." + ext) {
                base += "." + ext
            }
        }
        return base
    }
    
    fileprivate func mirrorToFiles(using f: FileManager, pathsExamined: Set<String>) throws -> String? {
        let mirrorPath = fileMirrorPath
        if skipMirrorAtNextSave || typeItems.count == 0 {
            return mirrorPath
        }
        if pathsExamined.contains(mirrorPath) { // some other drop has claimed this path
            return nil
        }
        let res: Bool
        if typeItems.count == 1 {
            res = try typeItems.first!.mirror(to: mirrorPath, using: f)
        } else {
            res = try mirrorFolder(to: mirrorPath, using: f)
        }
        if res {
            log("Mirrored item \(uuid.uuidString): \(displayTitleOrUuid)")
        }
        return mirrorPath
    }
    
    private func mirrorFolder(to path: String, using f: FileManager) throws -> Bool {
        
        if !f.fileExists(atPath: path) {
            try f.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            let url = URL(fileURLWithPath: path)
            f.setUUIDAttribute(MirrorManager.mirrorUuidKey, at: url, to: uuid)
        }
        
        var mirrored = false
        for child in typeItems {
            var childPath = path + "/" + child.filenameTypeIdentifier
            if let ext = child.fileExtension {
                childPath += "." + ext
            }
            if try child.mirror(to: childPath, using: f) {
                mirrored = true
            }
        }
        
        return mirrored
    }
        
    fileprivate func assimilateMirrorChanges() {

        if needsSaving || isTransferring || isDeleting || needsReIngest {
            return
        }
        
        var mirrorCount = 0
        for child in typeItems {
            if let url = child.assimilationUrl {
                
                log("Assimilating mirror changes into component \(child.uuid.uuidString)")
                try? FileManager.default.copyAndReplaceItem(at: url, to: child.bytesPath)
                child.markUpdated()
                
                mirrorCount += 1
            }
        }
        
        if mirrorCount == 0 {
            return
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
    
    fileprivate func mirror(to path: String, using f: FileManager) throws -> Bool {
                
        if !f.fileExists(atPath: bytesPath.path) {
            return false
        }
        
        var url = URL(fileURLWithPath: path)
        
        if f.fileExists(atPath: path) {
            if let fileDate = try? MirrorManager.modificationDate(for: url, using: f), fileDate >= updatedAt {
                return false
            } else {
                _ = try f.replaceItemAt(url, withItemAt: bytesPath, options: []) // explicitly empty options, to merge metadata
            }
        } else {
            try f.copyItem(at: bytesPath, to: url)
            f.setUUIDAttribute(MirrorManager.mirrorUuidKey, at: url, to: uuid)
        }
        
        var v = URLResourceValues()
        v.hasHiddenExtension = true
        v.creationDate = createdAt
        v.contentModificationDate = updatedAt
        try url.setResourceValues(v)
                
        return true
    }
    
    fileprivate var assimilationUrl: URL? {
        guard let parent = parent else {
            return nil
        }
        
        var path = parent.fileMirrorPath
        if parent.typeItems.count > 1 {
            path.append(filenameTypeIdentifier)
            if let ext = fileExtension {
                path.append("." + ext)
            }
        }
                
        let f = FileManager.default
        guard f.fileExists(atPath: path) else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        if let fileDate = try? MirrorManager.modificationDate(for: url, using: f), fileDate <= updatedAt {
            return nil
        }
        
        return url
    }
}
