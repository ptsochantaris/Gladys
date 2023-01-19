import CloudKit
import GladysCommon
import UIKit

extension CloudManager {
    private static func getDeviceId() -> Data {
        guard let identifier = UIDevice.current.identifierForVendor as NSUUID? else { return Data() }
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        identifier.getBytes(&uuidBytes)
        return Data(uuidBytes)
    }

    static func signalExtensionUpdate() async {
        guard syncSwitchedOn else { return }

        PersistedOptions.extensionRequestedSync = true

        let deviceUUID = "\(getDeviceId().base64EncodedString())/\(UUID().uuidString)"
        log("Updating extension update record: \(deviceUUID)")

        let recordType = RecordType.extensionUpdate.rawValue
        let updateRecord = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordType, zoneID: privateZoneId))
        updateRecord.setObject(deviceUUID as NSString, forKey: "deviceUUID")

        do {
            let modifyResults = try await container.privateCloudDatabase.modifyRecords(saving: [updateRecord], deleting: [], savePolicy: .allKeys)
            try check(modifyResults)
            log("Extension update posted")
        } catch {
            log("Extension update post failed: \(error.localizedDescription)")
        }
    }
}
