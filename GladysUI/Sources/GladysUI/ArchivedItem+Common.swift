import Foundation
import GladysCommon

public extension ArchivedItem {
    @MainActor
    var canPreview: Bool {
        components.contains { $0.canPreview }
    }

    func removeFromCloudkit() {
        cloudKitRecord = nil
        cloudKitShareRecord = nil
        for typeItem in components {
            typeItem.cloudKitRecord = nil
        }
    }

    @MainActor
    func delete() {
        if status.shouldDisplayLoading {
            cancelIngest()
        }

        status = .deleted
        if isImportedShare, let cloudKitShareRecord {
            Task { @CloudActor in
                CloudManager.markAsDeleted(recordName: cloudKitShareRecord.recordID.recordName, cloudKitRecord: cloudKitShareRecord)
            }
        } else if let cloudKitRecord {
            Task {
                await CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
            }
        } else {
            log("No cloud record for this item, skipping cloud delete")
        }
        let p = folderUrl.path
        let uuids = components.map(\.uuid)
        try? FileManager.default.removeItem(atPath: p)
        for item in uuids {
            clearCacheData(for: item)
        }
        clearCacheData(for: self.uuid) // this must be last since we use URLs above
    }

    func renumberTypeItems() {
        var count = 0
        for i in components {
            i.order = count
            count += 1
        }
    }

    var addedString: String {
        diskSizeFormatter.string(fromByteCount: sizeInBytes) + "\n" + shortDateFormatter.string(from: createdAt)
    }

    var previewableTypeItem: Component? {
        components.filter(\.canPreview).max { $0.contentPriority < $1.contentPriority }
    }

    static func updateUserActivity(_ activity: NSUserActivity, from item: ArchivedItem, child: Component?, titled: String) {
        activity.title = titled + " \"" + item.trimmedName + "\""

        let uuidString = item.uuid.uuidString
        let childUuidString = child?.uuid.uuidString

        var userInfo = [kGladysDetailViewingActivityItemUuid: uuidString]
        userInfo[kGladysDetailViewingActivityItemTypeUuid] = childUuidString
        activity.addUserInfoEntries(from: userInfo)

        activity.isEligibleForHandoff = true
        activity.isEligibleForPublicIndexing = false
        activity.targetContentIdentifier = [uuidString, childUuidString].compactMap { $0 }.joined(separator: "/")

        #if !os(macOS)
            activity.isEligibleForPrediction = true
        #endif
        activity.contentAttributeSet = item.searchAttributes
        activity.contentAttributeSet?.relatedUniqueIdentifier = uuidString
        activity.isEligibleForSearch = true
    }
}
