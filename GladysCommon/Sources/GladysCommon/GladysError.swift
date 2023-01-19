import Foundation

public enum GladysError: Int {
    case cloudAccountRetirevalFailed = 100
    case cloudLoginRequired
    case cloudAccessRestricted
    case cloudAccessTemporarilyUnavailable
    case cloudAccessNotSupported
    case importingArchiveFailed
    case unknownIngestError
    case actionCancelled
    case mainAppFailedToOpen
    case blankResponse
    case noData

    public var error: NSError {
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
        case .blankResponse: message = "The server returned an invalid response but not error"
        case .noData: message = "Data for this item could not be loaded"
        }
        return NSError(domain: "build.bru.Gladys.error",
                       code: rawValue,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}

public extension Error {
    var finalDescription: String {
        let err = self as NSError
        return (err.userInfo[NSUnderlyingErrorKey] as? NSError)?.finalDescription ?? err.localizedDescription
    }
}
