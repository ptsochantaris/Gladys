import Foundation

@MainActor
public enum DropStore {
    private static var uuidindex: [UUID: Int]?

    private static var dropStore = ContiguousArray<ArchivedItem>()

    public static func boot(with drops: ContiguousArray<ArchivedItem>) {
        dropStore = drops
        uuidindex = nil
    }

    public static var allDrops: ContiguousArray<ArchivedItem> {
        dropStore
    }

    public static func insert(drop: ArchivedItem, at index: Int) {
        dropStore.insert(drop, at: index)
        uuidindex = nil
    }

    public static func replace(drop: ArchivedItem, at index: Int) {
        dropStore[index] = drop
        uuidindex = nil
    }

    public static func removeDrop(at index: Int) {
        let item = dropStore.remove(at: index)
        uuidindex?[item.uuid] = nil
    }

    public static var dropsAreEmpty: Bool {
        dropStore.isEmpty
    }

    public static func sortDrops(by sequence: [UUID]) {
        if sequence.isEmpty { return }
        dropStore.sort { i1, i2 in
            let p1 = sequence.firstIndex(of: i1.uuid) ?? -1
            let p2 = sequence.firstIndex(of: i2.uuid) ?? -1
            return p1 < p2
        }
        uuidindex = nil
    }

    public static func removeDeletableDrops() {
        let count = dropStore.count
        dropStore.removeAll { $0.needsDeletion }
        if count != dropStore.count {
            uuidindex = nil
        }
    }

    public static func promoteDropsToTop(uuids: Set<UUID>) {
        let cut = dropStore.filter { uuids.contains($0.uuid) }
        if cut.isEmpty { return }
        dropStore.removeAll { uuids.contains($0.uuid) }
        dropStore.insert(contentsOf: cut, at: 0)
        uuidindex = nil
    }

    public static func append(drop: ArchivedItem) {
        uuidindex?[drop.uuid] = dropStore.count
        dropStore.append(drop)
    }

    public static func indexOfItem(with uuid: String) -> Int? {
        if let uuidData = UUID(uuidString: uuid) {
            return indexOfItem(with: uuidData)
        }
        return nil
    }

    public static func indexOfItem(with uuid: UUID) -> Int? {
        if let uuidindex {
            return uuidindex[uuid]
        } else {
            let z = zip(dropStore.map(\.uuid), 0 ..< dropStore.count)
            let newIndex = Dictionary(z) { one, _ in one }
            uuidindex = newIndex
            log("Rebuilt drop index")
            return newIndex[uuid]
        }
    }

    public static func item(uuid: UUID) -> ArchivedItem? {
        if let i = indexOfItem(with: uuid) {
            return dropStore[i]
        }
        return nil
    }

    public static func item(with uuid: String) -> Int? {
        if let uuidData = UUID(uuidString: uuid) {
            return indexOfItem(with: uuidData)
        }
        return nil
    }

    public static func contains(uuid: UUID) -> Bool {
        indexOfItem(with: uuid) != nil
    }

    public static func reset() {
        dropStore.removeAll(keepingCapacity: false)
        uuidindex = [:]
    }

    public static var doneIngesting: Bool {
        !dropStore.contains { ($0.needsReIngest && !$0.needsDeletion) || $0.loadingProgress != nil }
    }

    public static var readyToIngest: some Sequence<ArchivedItem> {
        dropStore.filter { $0.needsReIngest && !$0.needsDeletion && $0.loadingProgress == nil }
    }

    public static var visibleDrops: ContiguousArray<ArchivedItem> {
        dropStore.filter(\.isVisible)
    }

    public static func item(shareId: String) -> ArchivedItem? {
        dropStore.first { $0.cloudKitRecord?.share?.recordID.recordName == shareId }
    }

    public static func item(uuid: String) -> ArchivedItem? {
        if let uuidData = UUID(uuidString: uuid) {
            item(uuid: uuidData)
        } else {
            nil
        }
    }

    public static func component(uuid: String) -> Component? {
        if let uuidData = UUID(uuidString: uuid) {
            component(uuid: uuidData)
        } else {
            nil
        }
    }

    public static func component(uuid: UUID) -> Component? {
        for item in dropStore {
            if let componentIndex = item.components.firstIndex(where: { $0.uuid == uuid }) {
                return item.components[componentIndex]
            }
        }
        return nil
    }

    public static func sizeInBytes() async -> Int64 {
        let snapshot = DropStore.allDrops
        return await Task.detached {
            snapshot.reduce(0) { $0 + $1.sizeInBytes }
        }.value
    }

    public static func sizeForItems(uuids: [UUID]) async -> Int64 {
        let snapshot = DropStore.allDrops
        return await Task.detached {
            snapshot.reduce(0) { $0 + (uuids.contains($1.uuid) ? $1.sizeInBytes : 0) }
        }.value
    }

    public static var sharingMyItems: Bool {
        dropStore.contains { $0.shareMode == .sharing }
    }

    public static var containsImportedShares: Bool {
        dropStore.contains { $0.isImportedShare }
    }

    public static var itemsIAmSharing: ContiguousArray<ArchivedItem> {
        dropStore.filter { $0.shareMode == .sharing }
    }

    public static func reloadCells(for uuids: Set<UUID>) {
        for uuid in uuids {
            if let item = item(uuid: uuid) {
                item.postModified()
            }
        }
    }
}
