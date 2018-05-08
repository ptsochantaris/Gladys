
import UIKit
import CloudKit

final class ArchivedDropItem: Codable {

	let suggestedName: String?
	let uuid: UUID
	let createdAt:  Date

	var typeItems: [ArchivedDropItemType] {
		didSet {
			needsSaving = true
		}
	}
	var updatedAt: Date {
		didSet {
			needsSaving = true
		}
	}
	var needsReIngest: Bool {
		didSet {
			needsSaving = true
		}
	}
	var needsDeletion: Bool {
		didSet {
			needsSaving = true
		}
	}
	var note: String {
		didSet {
			needsSaving = true
		}
	}
	var titleOverride: String {
		didSet {
			needsSaving = true
		}
	}
	var labels: [String] {
		didSet {
			needsSaving = true
		}
	}

	var lockPassword: Data? {
		didSet {
			needsSaving = true
		}
	}

	var lockHint: String? {
		didSet {
			needsSaving = true
		}
	}

	// Transient
	var loadingProgress: Progress?
	var needsSaving: Bool
	var needsUnlock: Bool

	private enum CodingKeys : String, CodingKey {
		case suggestedName
		case typeItems
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
		try v.encode(typeItems, forKey: .typeItems)
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
		typeItems = try v.decode(Array<ArchivedDropItemType>.self, forKey: .typeItems)
		needsReIngest = try v.decodeIfPresent(Bool.self, forKey: .needsReIngest) ?? false
		note = try v.decodeIfPresent(String.self, forKey: .note) ?? ""
		titleOverride = try v.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
		labels = try v.decodeIfPresent([String].self, forKey: .labels) ?? []
		needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
		lockPassword = try v.decodeIfPresent(Data.self, forKey: .lockPassword)
		lockHint = try v.decodeIfPresent(String.self, forKey: .lockHint)
		needsSaving = false
		needsUnlock = lockPassword != nil
	}

	lazy var folderUrl: URL = {
		let url = Model.appStorageUrl.appendingPathComponent(self.uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try? f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}()

	#if MAINAPP || ACTIONEXTENSION

		static func importData(providers: [NSItemProvider], delegate: LoadCompletionDelegate?, overrides: ImportOverrides?) -> [ArchivedDropItem] {
			if PersistedOptions.separateItemPreference {
				var res = [ArchivedDropItem]()
				for p in providers {
					for t in sanitised(p.registeredTypeIdentifiers) {
						let item = ArchivedDropItem(providers: [p], delegate: delegate, limitToType: t, overrides: overrides)
						res.append(item)
					}
				}
				return res

			} else {
				let item = ArchivedDropItem(providers: providers, delegate: delegate, limitToType: nil, overrides: overrides)
				return [item]
			}
		}

		var loadCount = 0
		weak var delegate: LoadCompletionDelegate?

		private init(providers: [NSItemProvider], delegate: LoadCompletionDelegate?, limitToType: String?, overrides: ImportOverrides?) {

			uuid = UUID()
			createdAt = Date()
			updatedAt = createdAt
			suggestedName = providers.first!.suggestedName
			needsReIngest = true
			needsDeletion = false
			titleOverride = overrides?.title ?? ""
			note = overrides?.note ?? ""
			labels = overrides?.labels ?? []
			typeItems = [ArchivedDropItemType]()
			needsSaving = true
			needsUnlock = false
	
			loadingProgress = startIngest(providers: providers, delegate: delegate, limitToType: limitToType)
		}

	#endif

	init(from record: CKRecord, children: [CKRecord]) {
		let myUUID = UUID(uuidString: record.recordID.recordName)!
		uuid = myUUID
		createdAt = record["createdAt"] as! Date
		updatedAt = record["updatedAt"] as! Date
		suggestedName = record["suggestedName"] as? String
		titleOverride = record["titleOverride"] as! String
		lockPassword = record["lockPassword"] as? Data
		lockHint = record["lockHint"] as? String
		note = record["note"] as! String
		labels = (record["labels"] as? [String]) ?? []
		needsReIngest = true
		needsSaving = true
		needsDeletion = false
		needsUnlock = lockPassword != nil
		typeItems = children.map { ArchivedDropItemType(from: $0, parentUuid: myUUID) }.sorted { $0.order < $1.order }
		cloudKitRecord = record
	}

	#if MAINAPP || ACTIONEXTENSION || FILEPROVIDER
		var isDeleting = false

		var isTransferring: Bool {
			return typeItems.contains { $0.isTransferring }
		}

		var goodToSave: Bool { // TODO: Check if data transfer is occuring, NOT ingest
			return !isDeleting && !isTransferring
		}
	#endif
}
