#if MAC
    import Cocoa
#else
    import UIKit
#endif
import CloudKit

@globalActor
enum ComponentActor {
    final actor ActorType {}
    static let shared = ActorType()
}

final actor ComponentLookup {
    static let shared = ComponentLookup()
    
    private let componentLookup = NSMapTable<NSUUID, Component>(keyOptions: .strongMemory, valueOptions: .weakMemory)

    func register(_ component: Component) {
        componentLookup.setObject(component, forKey: component.uuid as NSUUID)
    }

    func lookup(uuid: UUID) -> Component? {
        componentLookup.object(forKey: uuid as NSUUID)
    }
}

final class Component: Codable {

    private enum CodingKeys: String, CodingKey {
        case typeIdentifier
        case representedClass
        case classWasWrapped
        case uuid
        case parentUuid
        case accessoryTitle
        case displayTitle
        case displayTitleAlignment
        case displayTitlePriority
        case displayIconPriority
        case displayIconContentMode
        case displayIconTemplate
        case createdAt
        case updatedAt
        case needsDeletion
        case order
    }

    @ComponentActor
    func encode(to encoder: Encoder) throws {
        var v = encoder.container(keyedBy: CodingKeys.self)
        try v.encode(typeIdentifier, forKey: .typeIdentifier)
        try v.encode(representedClass, forKey: .representedClass)
        try v.encode(classWasWrapped, forKey: .classWasWrapped)
        try v.encode(uuid, forKey: .uuid)
        try v.encode(parentUuid, forKey: .parentUuid)
        try v.encodeIfPresent(accessoryTitle, forKey: .accessoryTitle)
        try v.encodeIfPresent(displayTitle, forKey: .displayTitle)
        try v.encode(displayTitleAlignment.rawValue, forKey: .displayTitleAlignment)
        try v.encode(displayTitlePriority, forKey: .displayTitlePriority)
        try v.encode(displayIconContentMode.rawValue, forKey: .displayIconContentMode)
        try v.encode(displayIconPriority, forKey: .displayIconPriority)
        try v.encode(createdAt, forKey: .createdAt)
        try v.encode(updatedAt, forKey: .updatedAt)
        try v.encode(displayIconTemplate, forKey: .displayIconTemplate)
        try v.encode(needsDeletion, forKey: .needsDeletion)
        try v.encode(order, forKey: .order)
    }

    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
        representedClass = try v.decode(RepresentedClass.self, forKey: .representedClass)
        classWasWrapped = try v.decode(Bool.self, forKey: .classWasWrapped)

        uuid = try v.decode(UUID.self, forKey: .uuid)
        parentUuid = try v.decode(UUID.self, forKey: .parentUuid)

        accessoryTitle = try v.decodeIfPresent(String.self, forKey: .accessoryTitle)
        displayTitle = try v.decodeIfPresent(String.self, forKey: .displayTitle)
        displayTitlePriority = try v.decode(Int.self, forKey: .displayTitlePriority)
        displayIconPriority = try v.decode(Int.self, forKey: .displayIconPriority)
        displayIconTemplate = try v.decodeIfPresent(Bool.self, forKey: .displayIconTemplate) ?? false
        needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
        order = try v.decodeIfPresent(Int.self, forKey: .order) ?? 0

        let c = try v.decode(Date.self, forKey: .createdAt)
        createdAt = c
        updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c

        let a = try v.decode(Int.self, forKey: .displayTitleAlignment)
        displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

        let m = try v.decode(Int.self, forKey: .displayIconContentMode)
        displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center

        flags = []

        Task {
            await ComponentLookup.shared.register(self)
        }
    }

    var typeIdentifier: String
    var accessoryTitle: String?
    let uuid: UUID
    let parentUuid: UUID
    let createdAt: Date
    var updatedAt: Date
    var representedClass: RepresentedClass
    var classWasWrapped: Bool
    var needsDeletion: Bool
    var order: Int

    // ui
    var displayIconPriority: Int
    var displayIconContentMode: ArchivedDropItemDisplayType
    var displayIconTemplate: Bool
    var displayTitle: String?
    var displayTitlePriority: Int
    var displayTitleAlignment: NSTextAlignment

    struct Flags: OptionSet {
        let rawValue: UInt8
        static let isTransferring = Flags(rawValue: 1 << 0)
        static let loadingAborted = Flags(rawValue: 1 << 1)
    }

    var flags: Flags

    #if MAC
        var contributedLabels: [String]?
    #endif

    // Caches
    var encodedURLCache: (Bool, URL?)?
    var canPreviewCache: Bool?

    #if MAINAPP || MAC
        init(cloning item: Component, newParentUUID: UUID) {
            uuid = UUID()
            parentUuid = newParentUUID

            needsDeletion = false
            createdAt = Date()
            updatedAt = createdAt
            flags = []

            typeIdentifier = item.typeIdentifier
            accessoryTitle = item.accessoryTitle
            order = item.order
            displayIconPriority = item.displayIconPriority
            displayIconContentMode = item.displayIconContentMode
            displayTitlePriority = item.displayTitlePriority
            displayTitleAlignment = item.displayTitleAlignment
            displayIconTemplate = item.displayIconTemplate
            classWasWrapped = item.classWasWrapped
            representedClass = item.representedClass
            setBytes(item.bytes)

            Task {
                await ComponentLookup.shared.register(self)
            }
        }
    #endif

    #if MAINAPP || ACTIONEXTENSION || MAC
        init(typeIdentifier: String, parentUuid: UUID, data: Data, order: Int) {
            self.typeIdentifier = typeIdentifier
            self.order = order

            uuid = UUID()
            self.parentUuid = parentUuid

            displayIconPriority = 0
            displayIconContentMode = .center
            displayTitlePriority = 0
            displayTitleAlignment = .center
            displayIconTemplate = false
            classWasWrapped = false
            needsDeletion = false
            flags = []
            createdAt = Date()
            updatedAt = createdAt
            representedClass = .data
            setBytes(data)

            Task {
                await ComponentLookup.shared.register(self)
            }
        }

        init(typeIdentifier: String, parentUuid: UUID, order: Int) {
            self.typeIdentifier = typeIdentifier
            self.order = order

            uuid = UUID()
            self.parentUuid = parentUuid

            displayIconPriority = 0
            displayIconContentMode = .center
            displayTitlePriority = 0
            displayTitleAlignment = .center
            displayIconTemplate = false
            classWasWrapped = false
            needsDeletion = false
            createdAt = Date()
            updatedAt = createdAt
            representedClass = .unknown(name: "")
            flags = [.isTransferring]

            Task {
                await ComponentLookup.shared.register(self)
            }
        }
    #endif

    init(from record: CKRecord, parentUuid: UUID) {
        displayIconPriority = 0
        displayIconContentMode = .center
        displayTitlePriority = 0
        displayTitleAlignment = .center
        displayIconTemplate = false
        needsDeletion = false
        flags = []

        uuid = UUID(uuidString: record.recordID.recordName)!
        self.parentUuid = parentUuid

        createdAt = record["createdAt"] as? Date ?? .distantPast

        // this should be identical to cloudKitUpdate(from record: CKRecord)
        // duplicated because of Swift constructor requirements
        updatedAt = record["updatedAt"] as? Date ?? .distantPast
        typeIdentifier = record["typeIdentifier"] as? String ?? "public.data"
        representedClass = RepresentedClass(name: record["representedClass"] as? String ?? "")
        classWasWrapped = ((record["classWasWrapped"] as? Int ?? 0) != 0)

        accessoryTitle = record["accessoryTitle"] as? String
        order = record["order"] as? Int ?? 0
        if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
            try? FileManager.default.copyAndReplaceItem(at: assetURL, to: bytesPath)
        }
        cloudKitRecord = record

        Task {
            await ComponentLookup.shared.register(self)
        }
    }

    init(from typeItem: Component, newParent: ArchivedItem) {
        displayIconPriority = 0
        displayIconContentMode = .center
        displayTitlePriority = 0
        displayTitleAlignment = .center
        displayIconTemplate = false
        needsDeletion = false
        order = Int.max

        flags = []

        uuid = UUID()
        parentUuid = newParent.uuid

        createdAt = Date()
        updatedAt = Date()
        typeIdentifier = typeItem.typeIdentifier
        representedClass = typeItem.representedClass
        classWasWrapped = typeItem.classWasWrapped
        accessoryTitle = typeItem.accessoryTitle
        setBytes(typeItem.bytes)

        Task {
            await ComponentLookup.shared.register(self)
        }
    }

    var dataExists: Bool {
        FileManager.default.fileExists(atPath: bytesPath.path)
    }
}
