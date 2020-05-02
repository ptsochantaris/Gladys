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
        
        let updateRecord = CKRecord(recordType: RecordType.extensionUpdate, recordID: CKRecord.ID(recordName: "extensionRanOnDevice", zoneID: privateZoneId))

        let deviceUUID = getDeviceId() as NSData
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
