import CloudKit
import UIKit

extension CloudManager {

    private static func getDeviceId() -> Data {
        guard let identifier = UIDevice.current.identifierForVendor as NSUUID? else { return emptyData }
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        identifier.getBytes(&uuidBytes)
        return Data(uuidBytes)
    }

    static func signalExtensionUpdate() {
        guard syncSwitchedOn else { return }
        
        PersistedOptions.extensionRequestedSync = true
        
        let deviceUUID = "\(getDeviceId().base64EncodedString())/\(UUID().uuidString)"
        log("Updating extension update record: \(deviceUUID)")

        let recordType = RecordType.extensionUpdate.rawValue
        let updateRecord = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordType, zoneID: privateZoneId))
        updateRecord.setObject(deviceUUID as NSString, forKey: "deviceUUID")

        let operation = CKModifyRecordsOperation(recordsToSave: [updateRecord], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.perRecordCompletionBlock = { _, error in
            if let error = error {
                log("Extension update post failed: \(error.localizedDescription)")
            } else {
                log("Extension update posted")
            }
        }
        
        container.privateCloudDatabase.add(operation)
    }
}
