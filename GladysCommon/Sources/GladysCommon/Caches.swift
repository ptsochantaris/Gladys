import CloudKit
import Foundation

public final class CKRecordCacheEntry {
    public let record: CKRecord?
    public init(record: CKRecord?) {
        self.record = record
    }
}

public final class CKShareCacheEntry {
    public let share: CKShare?
    public init(share: CKShare?) {
        self.share = share
    }
}

public let folderUrlCache = Cache<UUID, URL>()
public let cloudKitDataPathCache = Cache<UUID, URL>()
public let cloudKitShareDataPathCache = Cache<UUID, URL>()
public let imagePathCache = Cache<UUID, URL>()
public let bytesPathCache = Cache<UUID, URL>()
public let cloudKitRecordCache = Cache<UUID, CKRecordCacheEntry>()
public let cloudKitShareCache = Cache<UUID, CKShareCacheEntry>()
public let needsCloudPushCache = Cache<UUID, Bool>()
public let presentationInfoCache = Cache<UUID, PresentationInfo>()

public func clearCacheData(for uuid: UUID) {
    folderUrlCache[uuid] = nil
    cloudKitDataPathCache[uuid] = nil
    cloudKitShareDataPathCache[uuid] = nil
    imagePathCache[uuid] = nil
    bytesPathCache[uuid] = nil
    cloudKitRecordCache[uuid] = nil
    cloudKitShareCache[uuid] = nil
    presentationInfoCache[uuid] = nil
}
