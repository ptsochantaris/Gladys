import CloudKit
import Foundation
import LRUCache

public struct CKRecordCacheEntry {
    public let record: CKRecord?
}

public struct CKShareCacheEntry {
    public let share: CKShare?
}

public extension LRUCache {
    subscript(key: Key) -> Value? {
        get {
            value(forKey: key)
        }
        set {
            setValue(newValue, forKey: key)
        }
    }
}

public let folderUrlCache = LRUCache<UUID, URL>()
public let bytesPathCache = LRUCache<UUID, URL>()
public let presentationInfoCache = LRUCache<UUID, PresentationInfo>()
public let encodedURLCache = LRUCache<UUID, (Bool, URL?)>()
public let canPreviewCache = LRUCache<UUID, Bool>()

public let cloudKitRecordCache = LRUCache<UUID, CKRecordCacheEntry>()
public let cloudKitShareCache = LRUCache<UUID, CKShareCacheEntry>()
public let cloudKitDataPathCache = LRUCache<UUID, URL>()
public let cloudKitShareDataPathCache = LRUCache<UUID, URL>()
public let needsCloudPushCache = LRUCache<UUID, Bool>()

public func clearCacheData(for uuid: UUID) {
    folderUrlCache[uuid] = nil
    bytesPathCache[uuid] = nil
    presentationInfoCache[uuid] = nil
    encodedURLCache[uuid] = nil
    canPreviewCache[uuid] = nil

    cloudKitRecordCache[uuid] = nil
    cloudKitShareCache[uuid] = nil
    cloudKitDataPathCache[uuid] = nil
    cloudKitShareDataPathCache[uuid] = nil
    needsCloudPushCache[uuid] = nil
    encodedURLCache[uuid] = nil
    bytesPathCache[uuid] = nil
}

public func clearCaches() {
    folderUrlCache.removeAll()
    bytesPathCache.removeAll()
    presentationInfoCache.removeAll()
    encodedURLCache.removeAll()
    canPreviewCache.removeAll()

    cloudKitRecordCache.removeAll()
    cloudKitShareCache.removeAll()
    cloudKitDataPathCache.removeAll()
    cloudKitShareDataPathCache.removeAll()
    needsCloudPushCache.removeAll()
    encodedURLCache.removeAll()
    bytesPathCache.removeAll()
}
