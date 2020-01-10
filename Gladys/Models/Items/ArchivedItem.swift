
import Foundation
import CloudKit

final class ArchivedItem: Codable {

	let suggestedName: String?
	let uuid: UUID
	let createdAt:  Date

	var components: ContiguousArray<Component> {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var updatedAt: Date {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var needsReIngest: Bool {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var needsDeletion: Bool {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var note: String {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var titleOverride: String {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var labels: [String] {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var lockPassword: Data? {
		didSet {
            flags.insert(.needsSaving)
		}
	}
	var lockHint: String? {
		didSet {
            flags.insert(.needsSaving)
		}
	}

	// Transient
    struct Flags: OptionSet {
        let rawValue: UInt8
        static let needsSaving          = Flags(rawValue: 1 << 0)
        static let needsUnlock          = Flags(rawValue: 1 << 1)
        static let isBeingCreatedBySync = Flags(rawValue: 1 << 2)
        static let skipMirrorAtNextSave = Flags(rawValue: 1 << 3)
    }

    var flags: Flags
	var loadingProgress: Progress?

	private enum CodingKeys : String, CodingKey {
		case suggestedName
		case components = "typeItems"
		case createdAt
		case updatedAt
		case uuid
		case needsReIngest
		case note
		case titleOverride
		case labels
		case needsDeletion
		case lockPassword
		case lockHint
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encodeIfPresent(suggestedName, forKey: .suggestedName)
		try v.encode(createdAt, forKey: .createdAt)
		try v.encode(updatedAt, forKey: .updatedAt)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(components, forKey: .components)
		try v.encode(needsReIngest, forKey: .needsReIngest)
		try v.encode(note, forKey: .note)
		try v.encode(titleOverride, forKey: .titleOverride)
		try v.encode(labels, forKey: .labels)
		try v.encode(needsDeletion, forKey: .needsDeletion)
		try v.encodeIfPresent(lockPassword, forKey: .lockPassword)
		try v.encodeIfPresent(lockHint, forKey: .lockHint)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		suggestedName = try v.decodeIfPresent(String.self, forKey: .suggestedName)
		let c = try v.decode(Date.self, forKey: .createdAt)
		createdAt = c
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c
		uuid = try v.decode(UUID.self, forKey: .uuid)
		components = try v.decode(ContiguousArray<Component>.self, forKey: .components)
		needsReIngest = try v.decodeIfPresent(Bool.self, forKey: .needsReIngest) ?? false
		note = try v.decodeIfPresent(String.self, forKey: .note) ?? ""
		titleOverride = try v.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
		labels = try v.decodeIfPresent([String].self, forKey: .labels) ?? []
		needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
		lockHint = try v.decodeIfPresent(String.self, forKey: .lockHint)
        lockPassword = try v.decodeIfPresent(Data.self, forKey: .lockPassword)
        flags = lockPassword == nil ? [] : .needsUnlock
	}

	#if MAINAPP || MAC
	init(cloning item: ArchivedItem) {
		let myUUID = UUID()
		uuid = myUUID

		createdAt = Date()
		updatedAt = createdAt
		lockPassword = nil
		lockHint = nil
		needsReIngest = true
		needsDeletion = false
        flags = .needsSaving

		titleOverride = item.titleOverride
		note = item.note
		suggestedName = item.suggestedName
		labels = item.labels

		components = ContiguousArray(item.components.map {
			Component(cloning: $0, newParentUUID: myUUID)
		})
	}
	#endif

	#if MAINAPP || ACTIONEXTENSION || INTENTSEXTENSION || MAC

	static func importData(providers: [NSItemProvider], overrides: ImportOverrides?) -> ContiguousArray<ArchivedItem> {
		if PersistedOptions.separateItemPreference {
			var res = ContiguousArray<ArchivedItem>()
			for p in providers {
				for t in sanitised(p.registeredTypeIdentifiers) {
					let item = ArchivedItem(providers: [p], limitToType: t, overrides: overrides)
					res.append(item)
				}
			}
			return res

		} else {
			let item = ArchivedItem(providers: providers, limitToType: nil, overrides: overrides)
			return [item]
		}
	}

	private init(providers: [NSItemProvider], limitToType: String?, overrides: ImportOverrides?) {

		uuid = UUID()
		createdAt = Date()
		updatedAt = createdAt
        #if MAC
        if #available(OSX 10.14, *) {
            suggestedName = providers.first!.suggestedName
        } else {
            suggestedName = nil
        }
        #else
		suggestedName = providers.first!.suggestedName
        #endif
		needsReIngest = false // original ingest, not re-ingest, show "cancel"
		needsDeletion = false
		titleOverride = overrides?.title ?? ""
		note = overrides?.note ?? ""
		labels = overrides?.labels ?? []
		components = ContiguousArray<Component>()
        flags = .needsSaving

		loadingProgress = startNewItemIngest(providers: providers, limitToType: limitToType)
	}

	var isTransferring: Bool {
		return components.contains { $0.isTransferring }
	}

	var goodToSave: Bool {
		return !needsDeletion && !isTransferring
	}
    
    var eligibleForExternalUpdateCheck: Bool {
        return !(needsDeletion || needsReIngest || flags.contains(.isBeingCreatedBySync) || loadingProgress != nil || shareMode == .elsewhereReadOnly)
    }

	init(from record: CKRecord) {
		let myUUID = UUID(uuidString: record.recordID.recordName)!
		uuid = myUUID

		createdAt = record["createdAt"] as? Date ?? .distantPast
		updatedAt = record["updatedAt"] as? Date ?? .distantPast
		titleOverride = record["titleOverride"] as? String ?? ""
		note = record["note"] as? String ?? ""

		suggestedName = record["suggestedName"] as? String
		lockPassword = record["lockPassword"] as? Data
		lockHint = record["lockHint"] as? String
		labels = (record["labels"] as? [String]) ?? []

		needsReIngest = true
        needsDeletion = false

        components = []

        if lockPassword == nil {
            flags = [.isBeingCreatedBySync, .needsSaving]
        } else {
            flags = [.isBeingCreatedBySync, .needsSaving, .needsUnlock]
        }

		cloudKitRecord = record
	}
	#endif
}
