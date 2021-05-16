import Foundation

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
        }
        return NSError(domain: "build.bru.Gladys.error",
                       code: self.rawValue,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}
