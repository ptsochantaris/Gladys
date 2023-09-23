import CloudKit
import Lista

extension CKRecord: @unchecked Sendable {}
extension CKDatabaseOperation: @unchecked Sendable {}
extension CKShare.Metadata: @unchecked Sendable {}
extension CKRecordZone: @unchecked Sendable {}

@globalActor
public enum CloudActor {
    public final actor ActorType {}
    public static let shared = ActorType()
}

public extension [[CKRecord]] {
    func flatBunch(minSize: Int) -> [Element] {
        let result = Lista<Element>()
        var newChild = Element()
        for childArray in self {
            newChild.append(contentsOf: childArray)
            if newChild.count >= minSize {
                result.append(newChild)
                newChild.removeAll(keepingCapacity: true)
            }
        }
        if newChild.isPopulated {
            result.append(newChild)
        }
        return Array(result)
    }
}

@CloudActor
public enum CloudManager {
    public enum RecordType: String {
        case item = "ArchivedDropItem"
        case component = "ArchivedDropItemType"
        case positionList = "PositionList"
        case share = "cloudkit.share"
        case extensionUpdate = "ExtensionUpdate"
    }

    public static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

    @UserDefault(key: "syncSwitchedOn", defaultValue: false)
    public static var syncSwitchedOn: Bool

    public static func check(_ results: ([CKRecordZone.ID: Result<CKRecordZone, Error>], [CKRecordZone.ID: Result<Void, Error>])) throws {
        try results.0.forEach { _ = try $0.value.get() }
        try results.1.forEach { _ = try $0.value.get() }
    }

    public static func check(_ results: ([CKRecord.ID: Result<CKRecord, Error>], [CKRecord.ID: Result<Void, Error>])) throws {
        try results.0.forEach { _ = try $0.value.get() }
        try results.1.forEach { _ = try $0.value.get() }
    }
}
