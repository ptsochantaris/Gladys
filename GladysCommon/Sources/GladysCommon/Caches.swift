import CloudKit
import Foundation

public struct CKRecordCacheEntry {
    public let record: CKRecord?
}

public struct CKShareCacheEntry {
    public let share: CKShare?
}

public let folderUrlCache = Cache<UUID, URL>()
public let bytesPathCache = Cache<UUID, URL>()
public let presentationInfoCache = Cache<UUID, PresentationInfo>()
public let encodedURLCache = Cache<UUID, (Bool, URL?)>()
public let canPreviewCache = Cache<UUID, Bool>()

public let cloudKitRecordCache = Cache<UUID, CKRecordCacheEntry>()
public let cloudKitShareCache = Cache<UUID, CKShareCacheEntry>()
public let cloudKitDataPathCache = Cache<UUID, URL>()
public let cloudKitShareDataPathCache = Cache<UUID, URL>()
public let needsCloudPushCache = Cache<UUID, Bool>()

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
    folderUrlCache.reset()
    bytesPathCache.reset()
    presentationInfoCache.reset()
    encodedURLCache.reset()
    canPreviewCache.reset()

    cloudKitRecordCache.reset()
    cloudKitShareCache.reset()
    cloudKitDataPathCache.reset()
    cloudKitShareDataPathCache.reset()
    needsCloudPushCache.reset()
    encodedURLCache.reset()
    bytesPathCache.reset()
}
