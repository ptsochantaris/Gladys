import CloudKit
import Foundation
import LRUCache

public nonisolated struct CKRecordCacheEntry: Sendable {
    public let record: CKRecord?
}

public nonisolated struct CKShareCacheEntry: Sendable {
    public let share: CKShare?
}

public nonisolated extension LRUCache {
    subscript(key: Key) -> Value? {
        get {
            value(forKey: key)
        }
        set {
            setValue(newValue, forKey: key)
        }
    }
}

public nonisolated extension PresentationInfo {
    /// Approximate bytes of decoded bitmap backing this entry, used as its eviction cost
    var cacheCost: Int {
        guard let cg = image?.getCgImage() else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}

/// Caches keyed by item identity that hold small computed values; bounded by entry count
private nonisolated let metadataCountLimit = 1000

/// Decoded thumbnail images can be large, so this cache is bounded by total bitmap memory
private nonisolated let presentationMemoryLimit = 128 * 1024 * 1024

public nonisolated let folderUrlCache = LRUCache<UUID, URL>(countLimit: metadataCountLimit)
public nonisolated let bytesPathCache = LRUCache<UUID, URL>(countLimit: metadataCountLimit)
public nonisolated let presentationInfoCache = LRUCache<UUID, PresentationInfo>(totalCostLimit: presentationMemoryLimit, countLimit: metadataCountLimit)
public nonisolated let encodedURLCache = LRUCache<UUID, (Bool, URL?)>(countLimit: metadataCountLimit)
public nonisolated let canPreviewCache = LRUCache<UUID, Bool>(countLimit: metadataCountLimit)

public nonisolated let cloudKitRecordCache = LRUCache<UUID, CKRecordCacheEntry>(countLimit: metadataCountLimit)
public nonisolated let cloudKitShareCache = LRUCache<UUID, CKShareCacheEntry>(countLimit: metadataCountLimit)
public nonisolated let cloudKitDataPathCache = LRUCache<UUID, URL>(countLimit: metadataCountLimit)
public nonisolated let cloudKitShareDataPathCache = LRUCache<UUID, URL>(countLimit: metadataCountLimit)
public nonisolated let needsCloudPushCache = LRUCache<UUID, Bool>(countLimit: metadataCountLimit)

public nonisolated func clearCacheData(for uuid: UUID) {
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

public nonisolated func clearCaches() {
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
