import CloudKit

public enum RecordChangeCheck {
    case none, changed, tagOnly

    public init(localRecord: CKRecord?, remoteRecord: CKRecord) {
        if localRecord?.recordChangeTag == remoteRecord.recordChangeTag {
            self = .none
        } else {
            let localModification = localRecord?.modificationDate ?? .distantPast
            let remoteModification = remoteRecord.modificationDate ?? .distantFuture
            if localModification < remoteModification {
                self = .changed
            } else {
                self = .tagOnly
            }
        }
    }
}

public extension CKDatabase.Scope {
    var keyName: String {
        switch self {
        case .public: return "1"
        case .private: return "2"
        case .shared: return "3"
        @unknown default: return "4"
        }
    }

    var logName: String {
        switch self {
        case .private: return "private"
        case .public: return "public"
        case .shared: return "shared"
        @unknown default: return "unknown"
        }
    }
}
