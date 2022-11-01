import CoreSpotlight
import Foundation

extension ArchivedItem {
    private static let dateFormatter: DateFormatter = {
        let d = DateFormatter()
        d.doesRelativeDateFormatting = true
        d.dateStyle = .short
        d.timeStyle = .short
        return d
    }()

    var shouldDisplayLoading: Bool {
        flags.contains(.isBeingCreatedBySync) || needsReIngest || loadingProgress != nil
    }

    func removeFromCloudkit() {
        cloudKitRecord = nil
        cloudKitShareRecord = nil
        for typeItem in components {
            typeItem.cloudKitRecord = nil
        }
    }

    var shareOwnerName: String? {
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
        if isImportedShare, let share = cloudKitShareRecord {
            CloudManager.markAsDeleted(recordName: share.recordID.recordName, cloudKitRecord: share)
        } else if cloudKitRecord != nil {
            CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
        } else {
            log("No cloud record for this item, skipping cloud delete")
        }
        removeIntents()
        let p = folderUrl.path
        dataAccessQueue.async(flags: .barrier) {
            let f = FileManager.default
            if f.fileExists(atPath: p) {
                try? f.removeItem(atPath: p)
            }
        }
        clearCacheData(for: uuid) // this must be last since we use URLs above
        for item in components {
            clearCacheData(for: item.uuid)
        }
    }

    func renumberTypeItems() {
        var count = 0
        for i in components {
            i.order = count
            count += 1
        }
    }

    func postModified() {
        Task { @MainActor in
            sendNotification(name: .ItemModified, object: self)
        }
    }

    var addedString: String {
        diskSizeFormatter.string(fromByteCount: sizeInBytes) + "\n" + ArchivedItem.dateFormatter.string(from: createdAt)
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
        if #available(macOS 10.15, *) {
            activity.targetContentIdentifier = [uuidString, childUuidString].compactMap { $0 }.joined(separator: "/")
        }

        #if MAC
            activity.isEligibleForSearch = false
        #else
            if #available(iOS 16, *) {
                activity.isEligibleForPrediction = false // using app intents
            } else {
                activity.isEligibleForPrediction = true
            }
            activity.contentAttributeSet = item.searchAttributes
            activity.contentAttributeSet?.relatedUniqueIdentifier = uuidString
            activity.isEligibleForSearch = true
        #endif
    }
}
