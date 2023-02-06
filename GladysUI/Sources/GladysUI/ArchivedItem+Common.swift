import Foundation
import GladysCommon
#if os(iOS)
    import Intents
#endif

public extension ArchivedItem {
    private func removeIntents() {
        #if os(iOS)
            INInteraction.delete(with: ["copy-\(uuid.uuidString)"])
            for item in components {
                item.removeIntents()
            }
        #endif
    }

    var shouldDisplayLoading: Bool {
        flags.contains(.isBeingCreatedBySync) || needsReIngest || loadingProgress != nil
    }

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

    private var shareOwnerName: String? {
        guard let p = cloudKitShareRecord?.owner.userIdentity.nameComponents else { return nil }
        let f = PersonNameComponentsFormatter()
        return f.string(from: p)
    }

    @MainActor
    func delete() {
        if shouldDisplayLoading {
            cancelIngest()
        }

        needsDeletion = true
        if isImportedShare, let cloudKitShareRecord {
            Task { @CloudActor in
                CloudManager.markAsDeleted(recordName: cloudKitShareRecord.recordID.recordName, cloudKitRecord: cloudKitShareRecord)
            }
        } else if let cloudKitRecord {
            Task { @CloudActor in
                CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
            }
        } else {
            log("No cloud record for this item, skipping cloud delete")
        }
        removeIntents()
        let p = folderUrl.path
        let uuids = components.map(\.uuid)
        itemAccessQueue.async(flags: .barrier) {
            componentAccessQueue.async(flags: .barrier) {
                try? FileManager.default.removeItem(atPath: p)
                for item in uuids {
                    clearCacheData(for: item)
                }
            }
            clearCacheData(for: self.uuid) // this must be last since we use URLs above
        }
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

        #if os(iOS)
            activity.isEligibleForPrediction = true
        #endif
        activity.contentAttributeSet = item.searchAttributes
        activity.contentAttributeSet?.relatedUniqueIdentifier = uuidString
        activity.isEligibleForSearch = true
    }
}
