import CloudKit

extension ArchivedItem {
    func cloudKitUpdate(from record: CKRecord) {
        updatedAt = record["updatedAt"] as? Date ?? .distantPast
        titleOverride = record["titleOverride"] as? String ?? ""
        note = record["note"] as? String ?? ""

        lockPassword = record["lockPassword"] as? Data
        lockHint = record["lockHint"] as? String
        labels = (record["labels"] as? [String]) ?? []

        if let colorString = record["highlightColor"] as? String, let color = ItemColor(rawValue: colorString) {
            highlightColor = color
        } else {
            highlightColor = .none
        }

        if isLocked {
            flags.insert(.needsUnlock)
        } else {
            flags.remove(.needsUnlock)
        }

        cloudKitRecord = record
        postModified()
    }

    var parentZone: CKRecordZone.ID {
        cloudKitRecord?.recordID.zoneID ?? privateZoneId
    }

    func sharedInZone(zoneId: CKRecordZone.ID) -> Bool {
        cloudKitRecord?.share?.recordID.zoneID == zoneId
    }

    var populatedCloudKitRecord: CKRecord? {
        guard needsCloudPush, !needsDeletion, goodToSave else { return nil }

        let record = cloudKitRecord ??
            CKRecord(recordType: CloudManager.RecordType.item.rawValue,
                     recordID: CKRecord.ID(recordName: uuid.uuidString, zoneID: privateZoneId))

        record.setValuesForKeys([
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "note": note,
            "titleOverride": titleOverride
        ])

        record["labels"] = labels.isEmpty ? nil : labels
        record["suggestedName"] = suggestedName
        record["lockPassword"] = lockPassword
        record["lockHint"] = lockHint
        record["highlightColor"] = highlightColor.rawValue
        return record
    }
}
