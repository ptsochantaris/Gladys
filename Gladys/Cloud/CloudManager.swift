import CloudKit

let diskSizeFormatter = ByteCountFormatter()

extension Sequence where Element: Hashable {
    var uniqued: [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}

extension Array {
    func bunch(maxSize: Int) -> [[Element]] {
        var pos = 0
        var slices = [ArraySlice<Element>]()
        while pos < count {
            let end = Swift.min(count, pos + maxSize)
            slices.append(self[pos ..< end])
            pos += maxSize
        }
        return slices.map { Array($0) }
    }
}

extension [[CKRecord]] {
    func flatBunch(minSize: Int) -> [[CKRecord]] {
        var result = [[CKRecord]]()
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
        return result
    }
}

extension Error {
    var itemDoesNotExistOnServer: Bool {
        (self as? CKError)?.code == CKError.Code.unknownItem
    }

    var changeTokenExpired: Bool {
        (self as? CKError)?.code == CKError.Code.changeTokenExpired
    }
}

@MainActor
enum CloudManager {
    enum RecordType: String {
        case item = "ArchivedDropItem"
        case component = "ArchivedDropItemType"
        case positionList = "PositionList"
        case share = "cloudkit.share"
        case extensionUpdate = "ExtensionUpdate"
    }

    static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")

    @UserDefault(key: "syncSwitchedOn", defaultValue: false)
    static var syncSwitchedOn: Bool

    static func check(_ results: ([CKRecordZone.ID: Result<CKRecordZone, Error>], [CKRecordZone.ID: Result<Void, Error>])) throws {
        try results.0.forEach { _ = try $0.value.get() }
        try results.1.forEach { _ = try $0.value.get() }
    }

    static func check(_ results: ([CKRecord.ID: Result<CKRecord, Error>], [CKRecord.ID: Result<Void, Error>])) throws {
        try results.0.forEach { _ = try $0.value.get() }
        try results.1.forEach { _ = try $0.value.get() }
    }
}
