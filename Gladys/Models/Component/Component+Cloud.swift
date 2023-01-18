import CloudKit
import GladysCommon

extension Component {
    func cloudKitUpdate(from record: CKRecord) {
        updatedAt = record["updatedAt"] as? Date ?? .distantPast
        typeIdentifier = record["typeIdentifier"] as? String ?? "public.data"
        representedClass = RepresentedClass(name: record["representedClass"] as? String ?? "")
        classWasWrapped = ((record["classWasWrapped"] as? Int ?? 0) != 0)

        accessoryTitle = record["accessoryTitle"] as? String
        order = record["order"] as? Int ?? 0
        if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
            try? FileManager.default.copyAndReplaceItem(at: assetURL, to: bytesPath)
        }
        cloudKitRecord = record
    }

    @MainActor
    var parentZone: CKRecordZone.ID {
        parent?.parentZone ?? privateZoneId
    }

    @MainActor
    var populatedCloudKitRecord: CKRecord? {
        let record = cloudKitRecord
            ?? CKRecord(recordType: "ArchivedDropItemType",
                        recordID: CKRecord.ID(recordName: uuid.uuidString, zoneID: parentZone))

        let parentId = CKRecord.ID(recordName: parentUuid.uuidString, zoneID: record.recordID.zoneID)
        record.parent = CKRecord.Reference(recordID: parentId, action: .none)
        record.setValuesForKeys([
            "parent": CKRecord.Reference(recordID: parentId, action: .deleteSelf),
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "typeIdentifier": typeIdentifier,
            "representedClass": representedClass.name,
            "classWasWrapped": classWasWrapped ? 1 : 0,
            "order": order
        ])

        record["accessoryTitle"] = accessoryTitle
        record["bytes"] = hasBytes ? CKAsset(fileURL: bytesPath) : nil
        return record
    }
}
