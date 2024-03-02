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
    case cloudLoginChanged
    case cloudLogoutDetected
    case cloudZoneWasDeleted
    case acceptRequiresSyncEnabled
    case syncFailure(CKError)
    case modelLoadingError(NSError)
    case modelCoordinationError(NSError)
    case creatingArchiveFailed

    public var suggestSettings: Bool {
        switch self {
        case .cloudLoginChanged, .cloudLoginRequired:
            true
        default:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .modelLoadingError(error):
            "This app's data store is not yet accessible. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(error.domain) - \(error.code): \(error.localizedDescription)\n\nIf this error persists, please report it to the developer."
        case let .modelCoordinationError(error):
            "Could not communicate with an extension. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(error.domain) - \(error.code): \(error.localizedDescription)\n\nIf this error persists, please report it to the developer."
        case .cloudZoneWasDeleted:
            "Your Gladys iCloud zone was deleted from another device. Sync was disabled in order to protect the data on this device.\n\nYou can re-create your iCloud data store with data from here if you turn sync back on again."
        case let .syncFailure(ckError):
            "There was an irrecoverable failure in sync and it was disabled:\n\n\"\(ckError.localizedDescription)\""
        case .acceptRequiresSyncEnabled:
            "You need to enable iCloud sync from preferences before accepting items shared in iCloud"
        case .cloudLoginChanged:
            "You have changed iCloud accounts. iCloud sync was disabled to keep your data safe. You can re-activate it to upload all your data to this account as well."
        case .cloudLogoutDetected:
            "You are not logged into iCloud anymore, so sync was disabled."
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
        case .creatingArchiveFailed:
            "Creating the archive failed"
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
