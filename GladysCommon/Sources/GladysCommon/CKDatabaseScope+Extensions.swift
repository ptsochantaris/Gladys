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
        case .public: "1"
        case .private: "2"
        case .shared: "3"
        @unknown default: "4"
        }
    }

    var logName: String {
        switch self {
        case .private: "private"
        case .public: "public"
        case .shared: "shared"
        @unknown default: "unknown"
        }
    }
}
