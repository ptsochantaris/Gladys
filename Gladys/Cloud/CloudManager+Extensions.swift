//
//  ScheduleAppRefresh.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 02/05/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import CloudKit

extension CloudManager {

    static func signalExtensionUpdate() {
        guard syncSwitchedOn else { return }
        
        let deviceUUID = getDeviceId().base64EncodedString() as NSString

        let updateRecord = CKRecord(recordType: RecordType.extensionUpdate, recordID: CKRecord.ID(recordName: RecordType.extensionUpdate, zoneID: privateZoneId))
        updateRecord.setObject(deviceUUID, forKey: "deviceUUID")

        let operation = CKModifyRecordsOperation(recordsToSave: [updateRecord], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.perRecordCompletionBlock = { _, error in
            if let error = error {
                log("Extension update posting failed: \(error.localizedDescription)")
            } else {
                log("Extension update posting done")
            }
        }
        
        container.privateCloudDatabase.add(operation)
    }
}
