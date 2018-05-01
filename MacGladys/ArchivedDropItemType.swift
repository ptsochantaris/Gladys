//
//  ArchivedDropItemType.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import CloudKit
import AVFoundation
import MapKit
import Fuzi
import ZIPFoundation

final class ArchivedDropItemType: Codable {

	private enum CodingKeys : String, CodingKey {
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
		case displayIconScale
		case displayIconWidth
		case displayIconHeight
		case displayIconTemplate
		case createdAt
		case updatedAt
		case needsDeletion
		case order
	}

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
		try v.encode(displayIconScale, forKey: .displayIconScale)
		try v.encode(displayIconWidth, forKey: .displayIconWidth)
		try v.encode(displayIconHeight, forKey: .displayIconHeight)
		try v.encode(createdAt, forKey: .createdAt)
		try v.encode(updatedAt, forKey: .updatedAt)
		try v.encode(displayIconTemplate, forKey: .displayIconTemplate)
		try v.encode(needsDeletion, forKey: .needsDeletion)
		try v.encode(order, forKey: .order)
	}

	lazy var imagePath: URL = {
		return self.folderUrl.appendingPathComponent("thumbnail.png")
	}()

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		representedClass = try v.decode(String.self, forKey: .representedClass)
		classWasWrapped = try v.decode(Bool.self, forKey: .classWasWrapped)
		uuid = try v.decode(UUID.self, forKey: .uuid)
		parentUuid = try v.decode(UUID.self, forKey: .parentUuid)
		accessoryTitle = try v.decodeIfPresent(String.self, forKey: .accessoryTitle)
		displayTitle = try v.decodeIfPresent(String.self, forKey: .displayTitle)
		displayTitlePriority = try v.decode(Int.self, forKey: .displayTitlePriority)
		displayIconPriority = try v.decode(Int.self, forKey: .displayIconPriority)
		displayIconScale = try v.decode(CGFloat.self, forKey: .displayIconScale)
		displayIconWidth = try v.decode(CGFloat.self, forKey: .displayIconWidth)
		displayIconHeight = try v.decode(CGFloat.self, forKey: .displayIconHeight)
		displayIconTemplate = try v.decodeIfPresent(Bool.self, forKey: .displayIconTemplate) ?? false
		needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
		order = try v.decodeIfPresent(Int.self, forKey: .order) ?? 0

		let c = try v.decode(Date.self, forKey: .createdAt)
		createdAt = c
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c

		let a = try v.decode(UInt.self, forKey: .displayTitleAlignment)
		displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

		let m = try v.decode(Int.self, forKey: .displayIconContentMode)
		displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center

		isTransferring = false
	}

	var encodedUrl: NSURL? {
		guard typeIdentifier == "public.url" || typeIdentifier == "public.file-url" else { return nil }

		let decoded = decode()
		if let u = decoded as? NSURL {
			return u
		} else if let array = decoded as? NSArray {
			for item in array {
				if let text = item as? String, let url = NSURL(string: text), let scheme = url.scheme, !scheme.isEmpty {
					return url
				}
			}
		} else if let d = decoded as? Data, let s = String(bytes: d, encoding: .utf8), let u = NSURL(string: s) {
			return u
		}
		return nil
	}

	lazy var bytesPath: URL = {
		return self.folderUrl.appendingPathComponent("blob", isDirectory: false)
	}()

	var bytes: Data? {
		set {
			let byteLocation = bytesPath
			if newValue == nil || loadingAborted {
				let f = FileManager.default
				if f.fileExists(atPath: byteLocation.path) {
					try? f.removeItem(at: byteLocation)
				}
			} else {
				try? newValue?.write(to: byteLocation, options: .atomic)
			}
		}
		get {
			let byteLocation = bytesPath
			if FileManager.default.fileExists(atPath: byteLocation.path) {
				return try! Data(contentsOf: byteLocation, options: [.alwaysMapped])
			} else {
				return nil
			}
		}
	}

	var typeIdentifier: String
	var accessoryTitle: String?
	let uuid: UUID
	let parentUuid: UUID
	let createdAt: Date
	var updatedAt: Date
	var representedClass: String
	var classWasWrapped: Bool
	var loadingError: Error?
	var needsDeletion: Bool
	var order: Int

	// transient / ui
	weak var delegate: LoadCompletionDelegate?
	var displayIconScale: CGFloat
	var displayIconWidth: CGFloat
	var displayIconHeight: CGFloat
	var loadingAborted = false
	var displayIconPriority: Int
	var displayIconContentMode: ArchivedDropItemDisplayType
	var displayIconTemplate: Bool
	var displayTitle: String?
	var displayTitlePriority: Int
	var displayTitleAlignment: NSTextAlignment
	var ingestCompletion: (()->Void)?
	var isTransferring: Bool

	var fileExtension: String? {
		let tag = UTTypeCopyPreferredTagWithClass(typeIdentifier as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue()
		if let tag = tag {
			let t = tag as String
			if !t.isEmpty {
				return t
			}
		}
		if typeIdentifier == "public.url" {
			return "url"
		}
		if typeIdentifier.hasSuffix("-plain-text") {
			return "txt"
		}
		return nil
	}

	var typeDescription: String? {

		if let desc = UTTypeCopyDescription(typeIdentifier as CFString)?.takeRetainedValue() {
			let t = desc as String
			if !t.isEmpty {
				return t.capitalized
			}
		}

		let id = typeIdentifier.lowercased()

		switch id {
		case "public.item": return "Item"
		case "public.content": return "Content"
		case "public.composite-content": return "Mixed Content"
		case "com.apple.application": return "Application"
		case "public.message": return "Message"
		case "public.contact": return "Contact"
		case "public.archive": return "Archive"
		case "public.disk-image": return "Disk Image"
		case "public.data": return "Data"
		case "public.directory": return "Directory"
		case "com.apple.resolvable": return "Alias"
		case "public.symlink": return "Symbolic Link"
		case "com.apple.mount-point": return "Mount Point"
		case "com.apple.alias-file": return "Alias File"
		case "public.url": return "Link"
		case "public.file-url": return "File Link"
		case "public.text": return "Text"
		case "public.plain-text": return "Plain Text"
		case "public.utf8-plain-text": return "Unicode Plain Text"
		case "public.utf16-external-plain-text": return "Unicode-16 Plain Text"
		case "public.utf16-plain-text": return "Unicode-16 Plain Text"
		case "public.rtf": return "Rich Text"
		case "public.html": return "HTML"
		case "public.xml": return "XML"
		case "public.xhtml": return "XHTML"
		case "com.adobe.pdf": return "Adobe PDF"
		case "com.apple.rtfd": return "Rich Text With Attachments Directory"
		case "com.apple.flat-rtfd": return "Rich Text With Attachments"
		case "com.apple.webarchive": return "Web Archive"
		case "com.adobe.postscript": return "PostScript"
		case "com.adobe.encapsulated-postscript": return "Encapsulated PostScript"
		case "public.presentation": return "Presentation"
		case "public.image": return "Image"
		case "public.jpeg": return "JPEG Image"
		case "public.jpeg-2000": return "JPEG-2000 Image"
		case "public.tiff": return "TIFF Image"
		case "com.apple.pict": return "Quickdraw PICT"
		case "com.compuserve.gif": return "GIF Image"
		case "public.png": return "PNG Image"
		case "com.apple.quicktime-image": return "QuickTime Image"
		case "com.apple.icns": return "Apple Icon Data"
		case "com.microsoft.bmp": return "BMP Image"
		case "com.microsoft.ico": return "ICO Image"
		case "public.fax": return "Fax"
		case "com.apple.macpaint-image": return "MacPaint Image"
		case "public.svg-image": return "SVG Image"
		case "public.xbitmap-image": return "XBMP Image"
		case "public.camera-raw-image": return "Camera Raw Image"
		case "com.adobe.photoshop-image": return "Photoshop Image"
		case "com.adobe.illustrator.ai-image": return "Illustrator document"
		case "com.truevision.tga-image": return "TGA image"
		case "com.sgi.sgi-image": return "Silicon Graphics Image"
		case "com.ilm.openexr-image": return "OpenEXR Image"
		case "com.kodak.flashpix-image": return "FlashPix Image"
		case "com.adobe.raw-image": return "Adobe Raw Image"
		case "com.canon.crw-raw-image": return "CRW Raw image"
		case "com.canon.cr2-raw-image": return "CR2 Raw Image"
		case "com.canon.tif-raw-image": return "TIF Raw Image"
		case "com.nikon.raw-image": return "Nikon Raw image"
		case "com.olympus.raw-image": return "Olympus Raw image"
		case "com.fuji.raw-image": return "Fuji Raw image"
		case "com.sony.raw-image": return "Sony Raw image"
		case "com.sony.arw-raw-image": return "Sony ARW Raw image"
		case "com.konicaminolta.raw-image": return "Minolta Raw image"
		case "com.kodak.raw-image": return "Kodak Raw image"
		case "com.panasonic.raw-image": return "Panasonic Raw image"
		case "com.pentax.raw-image": return "Pentax Raw image"
		case "com.leafamerica.raw-image": return "Leaf Raw image"
		case "com.leica.raw-image": return "Leica Raw image"
		case "com.hasselblad.fff-raw-image": return "Hasselblad FFF Raw image"
		case "com.hasselblad.3fr-raw-image": return "Hasselblad 3FR Raw image"
		case "public.audiovisual-content": return "AV Content"
		case "public.movie": return "Movie"
		case "public.video": return "Video"
		case "public.audio": return "Audio"
		case "com.apple.quicktime-movie": return "QuickTime Movie"
		case "public.mpeg": return "MPEG Movie"
		case "public.mpeg-4": return "MPEG-4 Movie"
		case "public.mp3": return "MP3 Audio"
		case "public.mpeg-4-audio": return "MPEG-4 Audio"
		case "com.apple.protected-mpeg-4-audio": return "Apple MPEG-4 Audio"
		case "public.mpeg-2-video": return "MPEG-2 Video"
		case "com.apple.protected-mpeg-4-video": return "Apple MPEG-4 Video"
		case "public.dv-movie": return "DV Movie"
		case "public.avi": return "AVI Movie"
		case "public.3gpp": return "3GPP Movie"
		case "public.3gpp2": return "3GPP2 Movie"
		case "com.microsoft.windows-media-wm": return "Windows Media"
		case "com.microsoft.windows-media-wmv": return "Windows Media"
		case "com.microsoft.windows-media-wmp": return "Windows Media"
		case "com.microsoft.windows-media-wma": return "Windows Media Audio"
		case "com.real.realmedia": return "RealMedia"
		case "com.real.realaudio": return "RealMedia Audio"
		case "public.ulaw-audio": return "uLaw Audio"
		case "public.au-audio": return "AU Audio"
		case "public.aifc-audio": return "AIFF-C Audio"
		case "public.aiff-audio": return "AIFF Audio"
		case "public.midi-audio": return "MIDI Audio"
		case "public.downloadable-sound": return "Downloadable Sound"
		case "com.apple.coreaudio-format": return "Apple CoreAudio"
		case "public.ac3-audio": return "AC-3 Audio"
		case "com.digidesign.sd2-audio": return "Sound Designer II Audio"
		case "com.microsoft.waveform-audio": return "Waveform Audio"
		case "com.soundblaster.soundfont": return "SoundFont Audio"
		case "public.folder": return "Folder"
		case "public.volume": return "Storage Volume"
		case "com.apple.package": return "File Package"
		case "com.apple.bundle": return "File Bundle"
		case "com.apple.application-bundle": return "Application Bundle"
		case "com.apple.application-file": return "Application"
		case "public.vcard": return "Contact Card"
		case "org.gnu.gnu-tar-archive": return "GNU tar Archive"
		case "public.tar-archive": return "tar Archive"
		case "org.gnu.gnu-zip-archive": return "GZip Archive"
		case "org.gnu.gnu-zip-tar-archive": return "gzip TAR Archive"
		case "public.bzip2-archive": return "Bzip2 Archive"
		case "public.tar-bzip2-archive": return "Bzip2 Compressed tar Archive"
		case "com.apple.binhex-archive": return "BinHex Archive"
		case "com.apple.macbinary-archive": return "MacBinary Archive"
		case "com.allume.stuffit-archive": return "Stuffit Archive"
		case "public.zip-archive": return "Zip Archive"
		case "com.pkware.zip-archive": return "PKZip Archive"
		case "com.microsoft.word.doc": return "Microsoft Word Document"
		case "com.microsoft.excel.xls": return "Microsoft Excel Workbook"
		case "com.microsoft.powerpoint.ppt": return "Microsoft PowerPoint Presentation"
		case "com.microsoft.word.wordml": return "Microsoft Word 2003 XML Document"
		case "com.apple.keynote.key": return "Keynote Document"
		case "com.apple.iwork.Keynote.key": return "Keynote Document"
		case "com.apple.keynote.kth": return "Keynote Document"
		case "com.apple.iwork.Keynote.kth": return "Keynote Theme"
		case "org.openxmlformats.openxml": return "Office Open XML"
		case "org.openxmlformats.wordprocessingml.document": return "Office Open XML Word Processor Document"
		case "org.openxmlformats.wordprocessingml.document.macroenabled": return "Office Open XML Word Processor Document (+macros)"
		case "org.openxmlformats.wordprocessingml.template": return "Office Open XML Word Processor Template"
		case "org.openxmlformats.wordprocessingml.template.macroenabled": return "Office Open XML Word Processor Template (+macros)"
		case "org.openxmlformats.spreadsheetml.sheet": return "Office Open XML Spreadsheet"
		case "org.openxmlformats.spreadsheetml.sheet.macroenabled": return "Office Open XML Spreadsheet (+macros)"
		case "org.openxmlformats.spreadsheetml.template": return "Office Open XML Spreadsheet Template"
		case "org.openxmlformats.spreadsheetml.template.macroenabled": return "Office Open XML Spreadsheet Template (+macros)"
		case "org.openxmlformats.presentationml.presentation": return "Office Open XML Presentation"
		case "org.openxmlformats.presentationml.presentation.macroenabled": return "Office Open XML Presentation (+macros)"
		case "org.openxmlformats.presentationml.slideshow": return "Office Open XML Slide Show"
		case "org.openxmlformats.presentationml.slideshow.macroenabled": return "Office Open XML Slide Show (macros enabled)"
		case "org.openxmlformats.presentationml.template": return "Office Open XML Presentation Template"
		case "org.openxmlformats.presentationml.template.macroenabled": return "Office Open XML Presentation Template (+macros)"
		case "org.oasis-open.opendocument": return "Open Document"
		case "org.oasis-open.opendocument.text": return "Open Document Text"
		case "org.oasis-open.opendocument.text-template": return "Open Document Text Template"
		case "org.oasis-open.opendocument.graphics": return "Open Document Graphics"
		case "org.oasis-open.opendocument.graphics-template": return "Open Document Graphics Template"
		case "org.oasis-open.opendocument.presentation": return "Open Document Presentation"
		case "org.oasis-open.opendocument.presentation-template": return "Open Document Presentation Template"
		case "org.oasis-open.opendocument.spreadsheet": return "Open Document Spreadsheet"
		case "org.oasis-open.opendocument.spreadsheet-template": return "Open Document Spreadsheet Template"
		case "org.oasis-open.opendocument.chart": return "Open Document Chart"
		case "org.oasis-open.opendocument.chart-template": return "Open Document Chart Template"
		case "org.oasis-open.opendocument.image": return "Open Document Image"
		case "org.oasis-open.opendocument.image-template": return "Open Document Image Template"
		case "org.oasis-open.opendocument.formula": return "Open Document Formula"
		case "org.oasis-open.opendocument.formula-template": return "Open Document Formula Template"
		case "org.oasis-open.opendocument.text-master": return "Open Document Text Master"
		case "org.oasis-open.opendocument.text-web": return "Open Document HTML Template"
		default: break
		}

		if id.hasSuffix("-source") && id.hasPrefix("public."),
			let lastComponent = id.components(separatedBy: ".").last,
			let lang = lastComponent.components(separatedBy: "-").first {
			return lang.capitalized + " Source"
		}

		if id.hasPrefix("com.apple.") {
			if id.contains(".iwork.") {
				if id.contains(".numbers") { return "Numbers Document" }
				if id.contains(".pages") { return "Pages Document" }
				if id.contains(".keynote") { return "Keynote Document" }
			}
		}

		if id.hasSuffix(".markdown") {
			return "Markdown Text"
		}

		switch representedClass {
		case "NSData": return "Data"
		case "NSString": return "Text"
		case "NSAttributedString": return "Rich Text"
		case "UIColor": return "Color"
		case "UIImage": return "Image"
		case "MKMapItem": return "Map Location"
		case "NSArray": return "List"
		case "NSDictionary": return "Associative List"
		case "URL": return "Link"
		default: break
		}

		return nil
	}

	func typeConforms(to parent: CFString) -> Bool {
		return UTTypeConformsTo(typeIdentifier as CFString, parent)
	}

	var contentDescription: String {
		if let typeDescription = typeDescription {
			return typeDescription
		} else if representedClass.isEmpty {
			return typeIdentifier
		} else {
			return "Other (\(representedClass))"
		}
	}

	var sizeInBytes: Int64 {

		func sizeItem(path: URL) -> Int64 {
			let fm = FileManager.default

			var isDir: ObjCBool = false
			if fm.fileExists(atPath: path.path, isDirectory: &isDir) {

				if isDir.boolValue {
					return fm.contentSizeOfDirectory(at: path)
				} else {
					if let attrs = try? fm.attributesOfItem(atPath: path.path) {
						return attrs[FileAttributeKey.size] as? Int64 ?? 0
					}
				}
			}
			return 0
		}

		return sizeItem(path: bytesPath)
	}

	func decode() -> Any? {
		guard let bytes = bytes else { return nil }

		// Do not do this because there may be a URL hidden there
		//if representedClass == "NSData" {
		//return bytes
		//}

		if classWasWrapped {
			return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(bytes) as Any
		} else if bytes.isPlist, let propertyList = (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) {
			return propertyList
		} else {
			return bytes
		}
	}

	var displayIcon: NSImage? {
		set {
			let ipath = imagePath
			if let n = newValue, let data = n.tiffRepresentation {
				try? data.write(to: ipath)
			} else if FileManager.default.fileExists(atPath: ipath.path) {
				try? FileManager.default.removeItem(at: ipath)
			}
		}
		get {
			let i = NSImage(contentsOf: imagePath)
			i?.isTemplate = displayIconTemplate
			return i
		}
	}

	lazy var folderUrl: URL = {
		let url = Model.appStorageUrl.appendingPathComponent(self.parentUuid.uuidString).appendingPathComponent(self.uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}()

	var filenameTypeIdentifier: String {
		return typeIdentifier.replacingOccurrences(of: ".", with: "-")
	}

	var oneTitle: String {
		return accessoryTitle ?? displayTitle ?? filenameTypeIdentifier
	}

	func markUpdated() {
		updatedAt = Date()
	}

	var backgroundInfoObject: (Any?, Int) {
		switch representedClass {
		case "MKMapItem": return (decode() as? MKMapItem, 30)
		default: return (nil, 0)
		}
	}

	init(typeIdentifier: String, parentUuid: UUID, data: Data, order: Int) {

		self.typeIdentifier = typeIdentifier
		self.parentUuid = parentUuid
		self.order = order

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		classWasWrapped = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		representedClass = "NSData"
		delegate = nil
		bytes = data
	}

	init(typeIdentifier: String, parentUuid: UUID, delegate: LoadCompletionDelegate, order: Int) {

		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.parentUuid = parentUuid
		self.order = order

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = true
		classWasWrapped = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		representedClass = ""
	}

	init(from record: CKRecord, parentUuid: UUID) {

		self.parentUuid = parentUuid

		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		needsDeletion = false

		let myUUID = record.recordID.recordName
		uuid = UUID(uuidString: myUUID)!
		createdAt = record["createdAt"] as! Date
		updatedAt = record["updatedAt"] as! Date
		typeIdentifier = record["typeIdentifier"] as! String
		representedClass = record["representedClass"] as! String
		classWasWrapped = (record["classWasWrapped"] as! Int != 0)
		accessoryTitle = record["accessoryTitle"] as? String
		order = record["order"] as? Int ?? 0
		if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
			let path = bytesPath
			let f = FileManager.default
			if f.fileExists(atPath: path.path) {
				try? f.removeItem(at: path)
			}
			try? f.copyItem(at: assetURL, to: path)
		}
		cloudKitRecord = record
	}

	init(from typeItem: ArchivedDropItemType, newParent: ArchivedDropItem) {
		parentUuid = newParent.uuid

		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		needsDeletion = false
		order = Int.max
		delegate = nil

		uuid = UUID()
		createdAt = Date()
		updatedAt = Date()
		typeIdentifier = typeItem.typeIdentifier
		representedClass = typeItem.representedClass
		classWasWrapped = typeItem.classWasWrapped
		accessoryTitle = typeItem.accessoryTitle
		bytes = typeItem.bytes
	}

	private var cloudKitDataPath: URL {
		return folderUrl.appendingPathComponent("ck-record", isDirectory: false)
	}

	var cloudKitRecord: CKRecord? {
		get {
			let recordLocation = cloudKitDataPath
			if FileManager.default.fileExists(atPath: recordLocation.path) {
				let data = try! Data(contentsOf: recordLocation, options: [])
				let coder = NSKeyedUnarchiver(forReadingWith: data)
				return CKRecord(coder: coder)
			} else {
				return nil
			}
		}
		set {
			let recordLocation = cloudKitDataPath
			if newValue == nil {
				let f = FileManager.default
				if f.fileExists(atPath: recordLocation.path) {
					try? f.removeItem(at: recordLocation)
				}
			} else {
				let data = NSMutableData()
				let coder = NSKeyedArchiver(forWritingWith: data)
				newValue?.encodeSystemFields(with: coder)
				coder.finishEncoding()
				try? data.write(to: recordLocation, options: .atomic)
			}
		}
	}

	private static let ingestQueue = DispatchQueue(label: "build.bru.Gladys.ingestQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	func startIngest(provider: NSItemProvider, delegate: LoadCompletionDelegate, encodeAnyUIImage: Bool) -> Progress {
		self.delegate = delegate
		let overallProgress = Progress(totalUnitCount: 3)

		let p = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
			guard let s = self, s.loadingAborted == false else { return }
			s.isTransferring = false
			if let data = data {
				ArchivedDropItemType.ingestQueue.async {
					log(">> Received type: [\(s.typeIdentifier)]")
					s.ingest(data: data, encodeAnyUIImage: encodeAnyUIImage) {
						overallProgress.completedUnitCount += 1
					}
				}
			} else {
				let error = error ?? NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown import error"])
				log(">> Error receiving item: \(error.finalDescription)")
				s.loadingError = error
				s.setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
				s.completeIngest()
				overallProgress.completedUnitCount += 1
			}
		}
		overallProgress.addChild(p, withPendingUnitCount: 2)
		return overallProgress
	}

	func reIngest(delegate: LoadCompletionDelegate) -> Progress {
		self.delegate = delegate
		let overallProgress = Progress(totalUnitCount: 3)
		overallProgress.completedUnitCount = 2
		if loadingError == nil, let bytesCopy = bytes {
			ArchivedDropItemType.ingestQueue.async { [weak self] in
				self?.ingest(data: bytesCopy) {
					overallProgress.completedUnitCount += 1
				}
			}
		} else {
			overallProgress.completedUnitCount += 1
			completeIngest()
		}
		return overallProgress
	}

	private func ingest(data: Data, encodeAnyUIImage: Bool = false, completion: @escaping ()->Void) { // in thread!

		ingestCompletion = completion

		let item: NSSecureCoding
		if data.isPlist, let obj = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? NSSecureCoding {
			log("      unwrapped keyed object: \(type(of:obj))")
			item = obj
			classWasWrapped = true

		} else {
			log("      looks like raw data")
			item = data as NSSecureCoding
		}

		if let item = item as? NSString {
			log("      received string: \(item)")
			setTitleInfo(item as String, 10)
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			representedClass = "NSString"
			bytes = data
			completeIngest()

		} else if let item = item as? NSAttributedString {
			log("      received attributed string: \(item)")
			setTitleInfo(item.string, 7)
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			representedClass = "NSAttributedString"
			bytes = data
			completeIngest()

		} else if let item = item as? MKMapItem {
			log("      received map item: \(item)")
			setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 10, .center)
			representedClass = "MKMapItem"
			bytes = data
			completeIngest()

		} else if let item = item as? URL {
			handleUrl(item, data)

		} else if let item = item as? NSArray {
			log("      received array: \(item)")
			if item.count == 1 {
				setTitleInfo("1 Item", 1)
			} else {
				setTitleInfo("\(item.count) Items", 1)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
			representedClass = "NSArray"
			bytes = data
			completeIngest()

		} else if let item = item as? NSDictionary {
			log("      received dictionary: \(item)")
			if item.count == 1 {
				setTitleInfo("1 Entry", 1)
			} else {
				setTitleInfo("\(item.count) Entries", 1)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
			representedClass = "NSDictionary"
			bytes = data
			completeIngest()

		} else {
			log("      received data: \(data)")
			representedClass = "NSData"
			handleData(data)
		}
	}

	private func appendDirectory(_ baseURL: URL, chain: [String], archive: Archive, fm: FileManager) throws {
		let joinedChain = chain.joined(separator: "/")
		let dirURL = baseURL.appendingPathComponent(joinedChain)
		for file in try fm.contentsOfDirectory(atPath: dirURL.path) {
			let newURL = dirURL.appendingPathComponent(file)
			var directory: ObjCBool = false
			if fm.fileExists(atPath: newURL.path, isDirectory: &directory) {
				if directory.boolValue {
					var newChain = chain
					newChain.append(file)
					try appendDirectory(baseURL, chain: newChain, archive: archive, fm: fm)
				} else {
					print("compressing file \(newURL)")
					let path = joinedChain + "/" + file
					try archive.addEntry(with: path, relativeTo: baseURL)
				}
			}
		}
	}

	private func handleUrl(_ item: URL, _ data: Data) {

		if item.isFileURL {
			let fm = FileManager.default
			var directory: ObjCBool = false
			if fm.fileExists(atPath: item.path, isDirectory: &directory) {
				do {
					let data: Data
					if directory.boolValue {
						let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/" + UUID().uuidString + ".zip")
						let a = Archive(url: tempURL, accessMode: .create)!
						let dirName = item.lastPathComponent
						let item = item.deletingLastPathComponent()
						try appendDirectory(item, chain: [dirName], archive: a, fm: fm)
						data = try Data(contentsOf: tempURL)
						try fm.removeItem(at: tempURL)
						typeIdentifier = kUTTypeZipArchive as String
						setDisplayIcon(#imageLiteral(resourceName: "zip"), 5, .center)
					} else {
						data = try Data(contentsOf: item)
						let ext = item.pathExtension
						if !ext.isEmpty, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
							typeIdentifier = uti as String
						}
						setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
					}
					accessoryTitle = item.lastPathComponent
					representedClass = "NSData"
					log("      read data from file url: \(item.absoluteString) - type assumed to be \(typeIdentifier)")
					handleData(data)

				} catch {
					bytes = data
					representedClass = "URL"
					setTitleInfo(item.lastPathComponent, 6)
					log("      could not read data from file, treating as local file url: \(item.absoluteString)")
					setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
					completeIngest()
				}
			} else {
				bytes = data
				representedClass = "URL"
				setTitleInfo(item.lastPathComponent, 6)
				log("      received local file url for non-existent file: \(item.absoluteString)")
				setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
				completeIngest()
			}

		} else {
			bytes = data
			representedClass = "URL"

			setTitleInfo(item.absoluteString, 6)
			log("      received remote url: \(item.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
			if let s = item.scheme, s.hasPrefix("http") {
				fetchWebPreview(for: item) { [weak self] title, image in
					if self?.loadingAborted ?? true { return }
					self?.accessoryTitle = title ?? self?.accessoryTitle
					if let image = image {
						if image.size.height > 100 || image.size.width > 200 {
							self?.setDisplayIcon(image, 30, .fit)
						} else {
							self?.setDisplayIcon(image, 30, .center)
						}
					}
					self?.completeIngest()
				}
			} else {
				completeIngest()
			}
		}
	}

	var isText: Bool {
		return !(typeConforms(to: kUTTypeVCard) || typeConforms(to: kUTTypeRTF)) && (typeConforms(to: kUTTypeText as CFString) || typeIdentifier == "com.apple.uikit.attributedstring")
	}

	var isRichText: Bool {
		return typeConforms(to: kUTTypeRTFD) || typeConforms(to: kUTTypeFlatRTFD) || typeIdentifier == "com.apple.uikit.attributedstring"
	}

	var textEncoding: String.Encoding {
		return typeConforms(to: kUTTypeUTF16PlainText) ? .utf16 : .utf8
	}

	private func handleData(_ data: Data) {
		bytes = data

		if (typeIdentifier == "public.folder" || typeIdentifier == "public.data") && data.isZip {
			typeIdentifier = "public.zip-archive"
		}

		if let image = NSImage(data: data) {
			setDisplayIcon(image, 50, .fill)

		} else if typeIdentifier == "public.vcard" {
			if let contacts = try? CNContactVCardSerialization.contacts(with: data), let person = contacts.first {
				let name = [person.givenName, person.middleName, person.familyName].filter({ !$0.isEmpty }).joined(separator: " ")
				let job = [person.jobTitle, person.organizationName].filter({ !$0.isEmpty }).joined(separator: ", ")
				accessoryTitle = [name, job].filter({ !$0.isEmpty }).joined(separator: " - ")

				if let imageData = person.imageData, let img = NSImage(data: imageData) {
					setDisplayIcon(img, 9, .circle)
				} else {
					setDisplayIcon(#imageLiteral(resourceName: "iconPerson"), 5, .center)
				}
			}

		} else if typeIdentifier == "public.utf8-plain-text" {
			if let s = String(data: data, encoding: .utf8) {
				setTitleInfo(s, 9)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeIdentifier == "public.utf16-plain-text" {
			if let s = String(data: data, encoding: .utf16) {
				setTitleInfo(s, 8)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeIdentifier == "public.email-message" {
			setDisplayIcon(#imageLiteral(resourceName: "iconEmail"), 10, .center)

		} else if typeIdentifier == "com.apple.mapkit.map-item" {
			setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 5, .center)

		} else if typeIdentifier.hasSuffix(".rtf") {
			if let s = (decode() as? NSAttributedString)?.string {
				setTitleInfo(s, 4)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeIdentifier.hasSuffix(".rtfd") {
			if let s = (decode() as? NSAttributedString)?.string {
				setTitleInfo(s, 4)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if let url = encodedUrl {
			handleUrl(url as URL, data)
			return // important

		} else if typeConforms(to: kUTTypeText as CFString) {
			if let s = String(data: data, encoding: .utf8) {
				setTitleInfo(s, 5)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeConforms(to: kUTTypeImage as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "image"), 5, .center)

		} else if typeConforms(to: kUTTypeAudiovisualContent as CFString) {
			if let moviePreview = generateMoviePreview() {
				setDisplayIcon(moviePreview, 50, .fill)
			} else {
				setDisplayIcon(#imageLiteral(resourceName: "movie"), 30, .center)
			}

		} else if typeConforms(to: kUTTypeAudio as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "audio"), 30, .center)

		} else if typeConforms(to: kUTTypePDF as CFString), let pdfPreview = generatePdfPreview() {
			if let title = getPdfTitle(), !title.isEmpty {
				setTitleInfo(title, 11)
			}
			setDisplayIcon(pdfPreview, 50, .fill)

		} else if typeConforms(to: kUTTypeContent as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)

		} else if typeConforms(to: kUTTypeArchive as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)

		} else {
			setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
		}

		completeIngest()
	}

	private func getPdfTitle() -> String? {
		if let document = CGPDFDocument(bytesPath as CFURL), let info = document.info {
			var titleStringRef: CGPDFStringRef?
			CGPDFDictionaryGetString(info, "Title", &titleStringRef)
			if let titleStringRef = titleStringRef, let s = CGPDFStringCopyTextString(titleStringRef), !(s as String).isEmpty {
				return s as String
			}
		}
		return nil
	}

	private func generatePdfPreview() -> NSImage? {
		guard let document = CGPDFDocument(bytesPath as CFURL), let firstPage = document.page(at: 1) else { return nil }

		let side: CGFloat = 1024

		var pageRect = firstPage.getBoxRect(.cropBox)
		let pdfScale = min(side / pageRect.size.width, side / pageRect.size.height)
		pageRect.origin = .zero
		pageRect.size.width = pageRect.size.width * pdfScale
		pageRect.size.height = pageRect.size.height * pdfScale

		let c = CGContext(data: nil,
						  width: Int(pageRect.size.width),
						  height: Int(pageRect.size.height),
						  bitsPerComponent: 8,
						  bytesPerRow: Int(pageRect.size.width) * 4,
						  space: CGColorSpaceCreateDeviceRGB(),
						  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)

		guard let context = c else { return nil }

		context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
		context.fill(pageRect)

		context.concatenate(firstPage.getDrawingTransform(.cropBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
		context.drawPDFPage(firstPage)

		if let cgImage = context.makeImage() {
			return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
		} else {
			return nil
		}
	}

	var previewTempPath: URL {
		if let f = fileExtension {
			return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gladys-preview-blob", isDirectory: false).appendingPathExtension(f)
		} else {
			return bytesPath
		}
	}

	private func generateMoviePreview() -> NSImage? {
		do {
			let fm = FileManager.default
			let tempPath = previewTempPath
			if fm.fileExists(atPath: tempPath.path) {
				try? fm.removeItem(at: tempPath)
			}
			try? fm.linkItem(at: bytesPath, to: tempPath)

			let asset = AVURLAsset(url: tempPath , options: nil)
			let imgGenerator = AVAssetImageGenerator(asset: asset)
			imgGenerator.appliesPreferredTrackTransform = true
			let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(0, 1), actualTime: nil)

			if fm.fileExists(atPath: tempPath.path) {
				try? fm.removeItem(at: tempPath)
			}
			return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))

		} catch let error {
			print("Error generating movie thumbnail: \(error.finalDescription)")
			return nil
		}
	}

	private func setLoadingError(_ message: String) {
		loadingError = NSError(domain: "build.build.Gladys.loadingError", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
		log("Error: \(message)")
	}

	func cancelIngest() {
		loadingAborted = true
		completeIngest()
	}

	private func setDisplayIcon(_ icon: NSImage, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) {
		guard priority >= displayIconPriority else {
			return
		}

		let result: NSImage
		if contentMode == .center || contentMode == .circle {
			result = icon
		} else if contentMode == .fit {
			result = icon.limited(to: CGSize(width: 256, height: 256), limitTo: 0.75, useScreenScale: true)
		} else {
			result = icon.limited(to: CGSize(width: 256, height: 256), useScreenScale: true)
		}
		displayIconScale = 1
		displayIconWidth = result.size.width
		displayIconHeight = result.size.height
		displayIconPriority = priority
		displayIconContentMode = contentMode
		displayIconTemplate = icon.isTemplate
		displayIcon = result
	}

	private static func webRequest(for url: URL) -> URLRequest {
		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String

		var request = URLRequest(url: url)
		request.setValue("Gladys/\(v) (iOS; iOS)", forHTTPHeaderField: "User-Agent")
		return request
	}

	private func fetchWebPreview(for url: URL, testing: Bool = true, completion: @escaping (String?, NSImage?)->Void) {

		// in thread!!

		var request = ArchivedDropItemType.webRequest(for: url)
		let U = uuid

		if testing {

			log("\(U): Investigating possible HTML title from this URL: \(url.absoluteString)")

			request.httpMethod = "HEAD"
			let headFetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.mimeType, type.hasPrefix("text/html") {
						log("\(U): Content for this is HTML, will try to fetch title")
						self.fetchWebPreview(for: url, testing: false, completion: completion)
					} else {
						log("\(U): Content for this isn't HTML, never mind")
						completion(nil, nil)
					}
				}
				if let error = error {
					log("\(U): Error while investigating URL: \(error.finalDescription)")
					completion(nil, nil)
				}
			}
			headFetch.resume()

		} else {

			log("\(U): Fetching HTML from URL: \(url.absoluteString)")

			let fetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let data = data,
					let text = (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)),
					let htmlDoc = try? HTMLDocument(string: text, encoding: .utf8) {

					let title = htmlDoc.title?.trimmingCharacters(in: .whitespacesAndNewlines)
					if let title = title {
						log("\(U): Title located at URL: \(title)")
					} else {
						log("\(U): No title located at URL")
					}

					var largestImagePath = "/favicon.ico"
					var imageRank = 0

					if let touchIcons = htmlDoc.head?.xpath("//link[@rel=\"apple-touch-icon\" or @rel=\"apple-touch-icon-precomposed\" or @rel=\"icon\" or @rel=\"shortcut icon\"]") {
						for node in touchIcons {
							let isTouch = node.attr("rel")?.hasPrefix("apple-touch-icon") ?? false
							var rank = isTouch ? 10 : 1
							if let sizes = node.attr("sizes") {
								let numbers = sizes.split(separator: "x").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
								if numbers.count > 1 {
									rank = (Int(numbers[0]) ?? 1) * (Int(numbers[1]) ?? 1) * (isTouch ? 100 : 1)
								}
							}
							if let href = node.attr("href") {
								if rank > imageRank {
									imageRank = rank
									largestImagePath = href
								}
							}
						}
					}

					var iconUrl: URL?
					if let i = URL(string: largestImagePath), i.scheme != nil {
						iconUrl = i
					} else {
						if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
							c.path = largestImagePath
							var url = c.url
							if url == nil && (!(largestImagePath.hasPrefix("/") || largestImagePath.hasPrefix("."))) {
								largestImagePath = "/" + largestImagePath
								c.path = largestImagePath
								url = c.url
							}
							iconUrl = url
						}
					}

					if let iconUrl = iconUrl {
						log("\(U): Fetching image for site icon: \(iconUrl)")
						ArchivedDropItemType.fetchImage(url: iconUrl) { newImage in
							completion(title, newImage)
						}
					} else {
						completion(title, nil)
					}

				} else if let error = error {
					log("\(U): Error while fetching title URL: \(error.finalDescription)")
					completion(nil, nil)
				} else {
					log("\(U): Bad HTML data while fetching title URL")
					completion(nil, nil)
				}
			}
			fetch.resume()
		}
	}

	private static func fetchImage(url: URL?, completion: @escaping (NSImage?)->Void) {
		guard let url = url else { completion(nil); return }
		let request = ArchivedDropItemType.webRequest(for: url)
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let data = data {
				log("Image fetched for \(url)")
				completion(NSImage(data: data))
			} else {
				log("Error fetching site icon from \(url)")
				completion(nil)
			}
			}.resume()
	}

	private func completeIngest() {
		let callback = ingestCompletion
		ingestCompletion = nil
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(sender: self)
			self.delegate = nil
			callback?()
		}
	}

	private func copyLocal(_ url: URL) -> URL {

		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		let f = FileManager.default
		do {
			if f.fileExists(atPath: newUrl.path) {
				try f.removeItem(at: newUrl)
			}
			try f.copyItem(at: url, to: newUrl)
		} catch {
			log("Error while copying item: \(error.finalDescription)")
			loadingError = error
		}
		return newUrl
	}

	private func setTitleInfo(_ text: String?, _ priority: Int) {

		let alignment: NSTextAlignment
		let finalText: String?
		if let text = text, text.count > 200 {
			alignment = .justified
			finalText = text.replacingOccurrences(of: "\n", with: " ")
		} else {
			alignment = .center
			finalText = text
		}
		let final = finalText?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\0", with: "")
		displayTitle = (final?.isEmpty ?? true) ? nil : final
		displayTitlePriority = priority
		displayTitleAlignment = alignment
	}

	static var droppedIds: Set<UUID>?

	func register(with provider: NSItemProvider) {
		provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
			let p = Progress(totalUnitCount: 1)
			p.completedUnitCount = 1
			DispatchQueue.global(qos: .userInitiated).async {
				log("Responding with data block")
				DispatchQueue.main.async {
					ArchivedDropItemType.droppedIds?.insert(self.parentUuid)
				}
				completion(self.dataForWrappedItem ?? self.bytes, nil)
			}
			return p
		}
	}

	var dataForWrappedItem: Data? {
		if classWasWrapped && typeIdentifier.hasPrefix("public.") {
			let decoded = decode()
			if let s = decoded as? String {
				return s.data(using: .utf8)
			} else if let s = decoded as? NSAttributedString {
				return try? s.data(from: NSMakeRange(0, s.string.count), documentAttributes: [:])
			} else if let s = decoded as? NSURL {
				return s.absoluteString?.data(using: .utf8)
			}
		}
		return nil
	}

	func deleteFromStorage() {
		let fm = FileManager.default
		if fm.fileExists(atPath: folderUrl.path) {
			log("Removing component storage at: \(folderUrl.path)")
			try? fm.removeItem(at: folderUrl)
		}
		CloudManager.markAsDeleted(uuid: uuid)
	}
}
