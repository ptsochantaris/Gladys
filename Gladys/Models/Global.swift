import Foundation
import CommonCrypto

#if os(iOS)
let groupName = "group.build.bru.Gladys"
let syncSchedulingRequestId = "build.bru.Gladys.scheduled.sync"
#else
let groupName = "X727JSJUGJ.build.bru.MacGladys"
#endif

let GladysFileUTI = "build.bru.gladys.archive"

let emptyData = Data()

enum GladysError: Int {
    case cloudAccountRetirevalFailed = 100
    case cloudLoginRequired
    case cloudAccessRestricted
    case cloudAccessTemporarilyUnavailable
    case cloudAccessNotSupported
    case importingArchiveFailed
    case unknownIngestError
    case actionCancelled
    case mainAppFailedToOpen
    
    var error: NSError {
        let message: String
        switch self {
        case .cloudAccessRestricted: message = "iCloud access is restricted on this device due to policy or parental controls."
        case .cloudAccountRetirevalFailed: message = "There was an error while trying to retrieve your account status."
        case .cloudLoginRequired: message = "You are not logged into iCloud on this device."
        case .cloudAccessNotSupported: message = "iCloud access is not available on this device."
        case .importingArchiveFailed: message = "Could not read imported archive."
        case .unknownIngestError: message = "Unknown item ingesting error."
        case .actionCancelled: message = "Action cancelled."
        case .mainAppFailedToOpen: message = "Main app could not be opened."
        case .cloudAccessTemporarilyUnavailable: message = "iCloud access is temporarily unavailable, you may need to re-sign in to your iCloud account."
        }
        return NSError(domain: "build.bru.Gladys.error",
                       code: self.rawValue,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func sha1(_ input: String) -> Data {
    return input.utf8CString.withUnsafeBytes { bytes -> Data in
        let len = Int(CC_SHA1_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: len)
        CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count), &digest)
        return Data(bytes: digest, count: len)
    }
}
