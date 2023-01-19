import CloudKit

public let diskSizeFormatter = ByteCountFormatter()

extension Sequence where Element: Hashable {
    public var uniqued: [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}

extension Array {
    public func bunch(maxSize: Int) -> [[Element]] {
        var pos = 0
        let slices = LinkedList<ArraySlice<Element>>()
        while pos < count {
            let end = Swift.min(count, pos + maxSize)
            slices.append(self[pos ..< end])
            pos += maxSize
        }
        return slices.map { Array($0) }
    }
}

extension [[CKRecord]] {
    public func flatBunch(minSize: Int) -> [[CKRecord]] {
        let result = LinkedList<[CKRecord]>()
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

extension Error {
    public var itemDoesNotExistOnServer: Bool {
        (self as? CKError)?.code == CKError.Code.unknownItem
    }

    public var changeTokenExpired: Bool {
        (self as? CKError)?.code == CKError.Code.changeTokenExpired
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
