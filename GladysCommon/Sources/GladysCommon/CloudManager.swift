import CloudKit
import Lista

extension CKRecord: @unchecked Sendable {}
extension CKDatabaseOperation: @unchecked Sendable {}
extension CKShare.Metadata: @unchecked Sendable {}
extension CKRecordZone: @unchecked Sendable {}

public let diskSizeFormatter = ByteCountFormatter()

public extension Sequence where Element: Hashable {
    var uniqued: [Element] {
        var set = Set<Element>()
        set.reserveCapacity(underestimatedCount)
        return filter { set.insert($0).inserted }
    }
}

public extension Array {
    func bunch(maxSize: Int) -> [[Element]] {
        var pos = 0
        let slices = Lista<ArraySlice<Element>>()
        while pos < count {
            let end = Swift.min(count, pos + maxSize)
            slices.append(self[pos ..< end])
            pos += maxSize
        }
        return slices.map { Array($0) }
    }
}

public extension [[CKRecord]] {
    func flatBunch(minSize: Int) -> [[CKRecord]] {
        let result = Lista<[CKRecord]>()
        var newChild = [CKRecord]()
        for childArray in self {
            newChild.append(contentsOf: childArray)
            if newChild.count >= minSize {
                result.append(newChild)
                newChild.removeAll(keepingCapacity: true)
            }
        }
        if !newChild.isEmpty {
            result.append(newChild)
        }
        return Array(result)
    }
}

@globalActor
public enum CloudActor {
    public final actor ActorType {}
    public static let shared = ActorType()
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
