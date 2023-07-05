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
        case .cloudAccessRestricted: return "iCloud access is restricted on this device due to policy or parental controls."
        case .cloudAccountRetirevalFailed: return "There was an error while trying to retrieve your account status."
        case .cloudLoginRequired: return "You are not logged into iCloud on this device."
        case .cloudAccessNotSupported: return "iCloud access is not available on this device."
        case .importingArchiveFailed: return "Could not read imported archive."
        case .unknownIngestError: return "Unknown item ingesting error."
        case .actionCancelled: return "Action cancelled."
        case .mainAppFailedToOpen: return "Main app could not be opened."
        case .cloudAccessTemporarilyUnavailable: return "iCloud access is temporarily unavailable, you may need to re-sign in to your iCloud account."
        case .blankResponse: return "The server returned an invalid response but not error"
        case .networkIssue: return "There was a network problem downloading this data"
        case .noData: return "Data for this item could not be loaded"
        }
    }
}

public extension Error {
    var itemDoesNotExistOnServer: Bool {
        (self as? CKError)?.code == CKError.Code.unknownItem
    }

    var changeTokenExpired: Bool {
        (self as? CKError)?.code == CKError.Code.changeTokenExpired
    }
}
