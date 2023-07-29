import CloudKit
import Foundation

public enum GladysError: LocalizedError {
    case cloudAccountRetirevalFailed
    case cloudLoginRequired
    case cloudAccessRestricted
    case cloudAccessTemporarilyUnavailable
    case cloudAccessNotSupported
    case importingArchiveFailed
    case unknownIngestError
    case actionCancelled
    case mainAppFailedToOpen
    case blankResponse
    case networkIssue
    case noData

    public var errorDescription: String? {
        switch self {
        case .cloudAccessRestricted:
            "iCloud access is restricted on this device due to policy or parental controls."
        case .cloudAccountRetirevalFailed:
            "There was an error while trying to retrieve your account status."
        case .cloudLoginRequired:
            "You are not logged into iCloud on this device."
        case .cloudAccessNotSupported:
            "iCloud access is not available on this device."
        case .importingArchiveFailed:
            "Could not read imported archive."
        case .unknownIngestError:
            "Unknown item ingesting error."
        case .actionCancelled:
            "Action cancelled."
        case .mainAppFailedToOpen:
            "Main app could not be opened."
        case .cloudAccessTemporarilyUnavailable:
            "iCloud access is temporarily unavailable, you may need to re-sign in to your iCloud account."
        case .blankResponse:
            "The server returned an invalid response but not error"
        case .networkIssue:
            "There was a network problem downloading this data"
        case .noData:
            "Data for this item could not be loaded"
        }
    }
}

public extension Error {
    var itemDoesNotExistOnServer: Bool {
        (self as? CKError)?.code == .unknownItem
    }

    var changeTokenExpired: Bool {
        (self as? CKError)?.code == .changeTokenExpired
    }
}
