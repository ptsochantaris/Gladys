#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
import AVFoundation
import CloudKit
import Contacts
import MapKit
import Semalot
import UniformTypeIdentifiers
import ZIPFoundation

public final class Component: Codable, Hashable {
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

    public func encode(to encoder: Encoder) throws {
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

    public init(from decoder: Decoder) throws {
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

        ComponentLookup.shared.register(self)
    }

    public var typeIdentifier: String
    public var accessoryTitle: String?
    public let uuid: UUID
    public let parentUuid: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var representedClass: RepresentedClass
    public var classWasWrapped: Bool
    public var needsDeletion: Bool
    public var order: Int

    // ui
    public var displayIconPriority: Int
    public var displayIconContentMode: ArchivedDropItemDisplayType
    public var displayIconTemplate: Bool
    public var displayTitle: String?
    public var displayTitlePriority: Int
    public var displayTitleAlignment: NSTextAlignment

    public struct Flags: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let isTransferring = Flags(rawValue: 1 << 0)
        public static let loadingAborted = Flags(rawValue: 1 << 1)
    }

    public var flags: Flags

    public var contributedLabels: [String]?

    // Caches
    public var encodedURLCache: (Bool, URL?)?
    public var canPreviewCache: Bool?

    public init(cloning item: Component, newParentUUID: UUID) {
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

        ComponentLookup.shared.register(self)
    }

    public init(typeIdentifier: String, parentUuid: UUID, data: Data, order: Int) {
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

        ComponentLookup.shared.register(self)
    }

    public init(typeIdentifier: String, parentUuid: UUID, order: Int) {
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

        ComponentLookup.shared.register(self)
    }

    public init(from record: CKRecord, parentUuid: UUID) {
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

        ComponentLookup.shared.register(self)
    }

    public init(from typeItem: Component, newParent: ArchivedItem) {
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

        ComponentLookup.shared.register(self)
    }

    public var dataExists: Bool {
        FileManager.default.fileExists(atPath: bytesPath.path)
    }

    //////////////////////////////////////////// Common

    public func getFolderUrl(createIfNeeded: Bool) -> URL {
        if let url = folderUrlCache[uuid] {
            return url as URL
        }

        let url = appStorageUrl.appendingPathComponent(parentUuid.uuidString).appendingPathComponent(uuid.uuidString)
        if createIfNeeded {
            let f = FileManager.default
            if !f.fileExists(atPath: url.path) {
                try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
            folderUrlCache[uuid] = url
        }
        return url
    }

    public var folderUrl: URL {
        getFolderUrl(createIfNeeded: true)
    }

    public var imagePath: URL {
        if let url = imagePathCache[uuid] {
            return url as URL
        }

        let url = getFolderUrl(createIfNeeded: true).appendingPathComponent("thumbnail.png")
        imagePathCache[uuid] = url
        return url
    }

    public func getBytesPath(createIfNeeded: Bool) -> URL {
        if let url = bytesPathCache[uuid] {
            return url as URL
        }

        let url = getFolderUrl(createIfNeeded: createIfNeeded).appendingPathComponent("blob", isDirectory: false)
        bytesPathCache[uuid] = url
        return url
    }

    public var bytesPath: URL {
        getBytesPath(createIfNeeded: true)
    }

    public static let lastModificationKey = "build.bru.Gladys.lastGladysModification"
    public var lastGladysBlobUpdate: Date? { // be sure to protect with dataAccessQueue
        get {
            FileManager.default.getDateAttribute(Component.lastModificationKey, from: bytesPath)
        }
        set {
            FileManager.default.setDateAttribute(Component.lastModificationKey, at: bytesPath, to: newValue)
        }
    }

    public func setBytes(_ data: Data?) {
        let byteLocation = bytesPath
        componentAccessQueue.async(flags: .barrier) {
            if data == nil || self.flags.contains(.loadingAborted) {
                let f = FileManager.default
                if f.fileExists(atPath: byteLocation.path) {
                    try? f.removeItem(at: byteLocation)
                }
            } else {
                try? data?.write(to: byteLocation)
                self.lastGladysBlobUpdate = Date()
            }
        }
    }

    public var filenameTypeIdentifier: String {
        typeIdentifier.replacingOccurrences(of: ".", with: "-")
    }

    public var oneTitle: String {
        accessoryTitle ?? displayTitle ?? filenameTypeIdentifier
    }

    public func decode() -> Any? {
        guard let bytes else { return nil }

        // Do not do this because there may be a URL hidden there
        // if representedClass == "NSData" {
        // return bytes
        // }

        if classWasWrapped, let unarchived = SafeArchiving.unarchive(bytes) {
            return unarchived
        } else if isPlist, let propertyList = (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) {
            return propertyList
        } else {
            return bytes
        }
    }

    public var bytes: Data? {
        componentAccessQueue.sync {
            Data.forceMemoryMapped(contentsOf: bytesPath)
        }
    }

    public var hasBytes: Bool {
        componentAccessQueue.sync {
            FileManager.default.fileExists(atPath: bytesPath.path)
        }
    }

    public var isPlist: Bool {
        bytes?.isPlist ?? false
    }

    public var encodedUrl: URL? {
        if let encodedURLCache {
            return encodedURLCache.1
        }

        var ret: URL?
        if isURL {
            let decoded = decode()
            if let u = decoded as? URL {
                ret = u
            } else if let array = decoded as? NSArray {
                for item in array {
                    if let text = item as? String, let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty {
                        ret = url
                        break
                    }
                }
            } else if let d = decoded as? Data, let s = String(bytes: d, encoding: .utf8), let u = URL(string: s) {
                ret = u
            }
        }

        encodedURLCache = (true, ret)
        return ret
    }

    public var fileExtension: String? {
        if let type = UTType(typeIdentifier), let ext = type.preferredFilenameExtension {
            return ext
        }
        if isURL {
            return "url"
        }
        if typeIdentifier.hasSuffix("-plain-text") {
            return "txt"
        }
        return nil
    }

    public var isURL: Bool {
        typeConforms(to: .url)
    }

    public var isWebURL: Bool {
        if let e = encodedUrl {
            return e.scheme != "file"
        }
        return false
    }

    public var isFileURL: Bool {
        if let e = encodedUrl {
            return e.scheme == "file"
        }
        return false
    }

    public var isWebArchive: Bool {
        typeIdentifier == "com.apple.webarchive"
    }

    public var typeDescription: String {
        if let type = UTType(typeIdentifier) {
            return type.description
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

        if id.hasSuffix("-source"), id.hasPrefix("public."),
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

        return representedClass.description
    }

    public var contentPriority: Int {
        if typeIdentifier == "com.apple.mapkit.map-item" { return 90 }

        if typeConforms(to: .vCard) { return 80 }

        if isWebURL { return 70 }

        if typeConforms(to: .video) { return 60 }

        if typeConforms(to: .audio) { return 50 }

        if typeConforms(to: .pdf) { return 40 }

        if typeConforms(to: .image) { return 30 }

        if typeConforms(to: .text) { return 20 }

        if isFileURL { return 10 }

        return 0
    }

    public func typeConforms(to parent: UTType) -> Bool {
        UTType(typeIdentifier)?.conforms(to: parent) ?? false
    }

    public var sizeInBytes: Int64 {
        componentAccessQueue.sync {
            let fm = FileManager.default

            var isDir: ObjCBool = false
            let url = getBytesPath(createIfNeeded: false)
            let path = url.path
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return fm.contentSizeOfDirectory(at: url)
                } else {
                    if let attrs = try? fm.attributesOfItem(atPath: path) {
                        return attrs[FileAttributeKey.size] as? Int64 ?? 0
                    }
                }
            }
            return 0
        }
    }

    private var cloudKitDataPath: URL {
        if let url = cloudKitDataPathCache[uuid] {
            return url as URL
        }

        let url = folderUrl.appendingPathComponent("ck-record", isDirectory: false)
        cloudKitDataPathCache[uuid] = url
        return url
    }

    public var cloudKitRecord: CKRecord? {
        get {
            if let cached = cloudKitRecordCache[uuid] {
                return cached.record
            }
            let recordLocation = cloudKitDataPath
            return componentAccessQueue.sync {
                if let data = try? Data(contentsOf: recordLocation), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
                    let record = CKRecord(coder: coder)
                    coder.finishDecoding()
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: record)
                    return record

                } else {
                    cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: nil)
                    return nil
                }
            }
        }
        set {
            cloudKitRecordCache[uuid] = CKRecordCacheEntry(record: newValue)
            let recordLocation = cloudKitDataPath
            componentAccessQueue.async(flags: .barrier) {
                if let newValue {
                    let coder = NSKeyedArchiver(requiringSecureCoding: true)
                    newValue.encodeSystemFields(with: coder)
                    try? coder.encodedData.write(to: recordLocation)
                } else {
                    let f = FileManager.default
                    if f.fileExists(atPath: recordLocation.path) {
                        try? f.removeItem(at: recordLocation)
                    }
                }
            }
        }
    }

    public func cancelIngest() {
        flags.insert(.loadingAborted)
    }

    public func clearCachedFields() {
        encodedURLCache = nil
        canPreviewCache = nil
    }

    #if canImport(AppKit)
        public var componentIcon: NSImage? {
            get {
                guard let d = try? Data(contentsOf: imagePath), let i = NSImage(data: d) else {
                    return nil
                }
                if displayIconTemplate {
                    i.isTemplate = true
                    let w = i.size.width
                    let h = i.size.height
                    let scale = min(32.0 / h, 32.0 / w)
                    i.size = NSSize(width: w * scale, height: h * scale)
                }
                return i
            }
            set {
                let ipath = imagePath
                if let n = newValue, let data = n.tiffRepresentation {
                    try? data.write(to: ipath)
                } else if FileManager.default.fileExists(atPath: ipath.path) {
                    try? FileManager.default.removeItem(at: ipath)
                }
            }
        }

    public var thumbnail: NSImage? {
        nil
    }
    #else
        public var componentIcon: UIImage? {
            get {
                UIImage.fromFile(imagePath, template: displayIconTemplate)
            }
            set {
                let ipath = imagePath
                if let n = newValue, let data = n.pngData() {
                    try? data.write(to: ipath)
                } else {
                    try? FileManager.default.removeItem(at: ipath)
                }
            }
        }

        public var thumbnail: UIImage? {
            get {
                if displayIconTemplate {
                    return UIImage.fromFile(imagePath, template: true)
                } else {
                    return UIImage.fromFile(imagePath, template: false)?.limited(to: CGSize(width: 128, height: 128), singleScale: true)
                }
            }
        }
    #endif

    public static func == (lhs: Component, rhs: Component) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    public static let iconPointSize = CGSize(width: 256, height: 256)

    public var backgroundInfoObject: (Any?, Int) {
        switch representedClass {
        case .mapItem: (decode() as? MKMapItem, 30)
        case .color: (decode() as? COLOR, 30)
        default: (nil, 0)
        }
    }

    func startIngest(provider: NSItemProvider, encodeAnyUIImage: Bool, createWebArchive: Bool, progress: Progress) async throws {
        progress.totalUnitCount = 2

        do {
            let data = try await provider.loadDataRepresentation(for: createWebArchive ? "public.url" : typeIdentifier)
            progress.completedUnitCount += 1
            flags.remove(.isTransferring)
            if flags.contains(.loadingAborted) {
                throw GladysError.actionCancelled
            }

            if createWebArchive {
                var assignedUrl: URL?
                if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    if let urlString = propertyList as? String, let u = URL(string: urlString) { // usually on macOS
                        assignedUrl = u
                    } else if let array = propertyList as? [Any], let urlString = array.first as? String, let u = URL(string: urlString) { // usually on iOS
                        assignedUrl = u
                    }
                }

                guard let assignedUrl else {
                    throw GladysError.actionCancelled
                }

                log(">> Resolved url to read data from: [\(typeIdentifier)]")
                try await ingest(from: assignedUrl)

            } else {
                log(">> Received type: [\(typeIdentifier)]")
                try await ingest(data: data, encodeAnyUIImage: encodeAnyUIImage, storeBytes: true)
            }

            progress.completedUnitCount += 1

        } catch {
            flags.remove(.isTransferring)
            try await ingestFailed(error: error)
        }
    }

    private func ingestFailed(error: Error?) async throws {
        let error = error ?? GladysError.unknownIngestError
        log(">> Error receiving item: \(error.localizedDescription)")
        await setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
        throw error
    }

    private func ingest(from url: URL) async throws {
        // in thread!

        clearCachedFields()
        representedClass = .data
        classWasWrapped = false

        if let scheme = url.scheme, !scheme.hasPrefix("http") {
            try await handleData(Data(), resolveUrls: false, storeBytes: true)
            return
        }

        let (data, _) = try await WebArchiver.shared.archiveFromUrl(url.absoluteString)
        if flags.contains(.loadingAborted) {
            try await ingestFailed(error: nil)
        }

        try await handleData(data, resolveUrls: false, storeBytes: true)
    }

    private static let gateKeeper = Semalot(tickets: 10)

    private func ingest(data: Data, encodeAnyUIImage: Bool = false, storeBytes: Bool) async throws {
        // in thread!
        await Component.gateKeeper.takeTicket()
        defer {
            Component.gateKeeper.returnTicket()
        }

        clearCachedFields()

        if data.isPlist, let obj = SafeArchiving.unarchive(data) {
            log("      unwrapped keyed object: \(type(of: obj))")
            classWasWrapped = true

            if let item = obj as? NSString {
                log("      received string: \(item)")
                setTitleInfo(item as String, 10)
                await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
                representedClass = .string
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? NSAttributedString {
                log("      received attributed string: \(item)")
                setTitleInfo(item.string, 7)
                await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
                representedClass = .attributedString
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? COLOR {
                log("      received color: \(item)")
                setTitleInfo("Color \(item.hexValue)", 0)
                await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 0, .center)
                representedClass = .color
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? IMAGE {
                log("      received image: \(item)")
                await setDisplayIcon(item, 50, .fill)
                if encodeAnyUIImage {
                    log("      will encode it to JPEG, as it's the only image in this parent item")
                    representedClass = .data
                    typeIdentifier = UTType.jpeg.identifier
                    classWasWrapped = false
                    if storeBytes {
                        #if canImport(AppKit)
                            let b = (item.representations.first as? NSBitmapImageRep)?.representation(using: .jpeg, properties: [:])
                            setBytes(b ?? Data())
                        #else
                            let b = item.jpegData(compressionQuality: 1)
                            setBytes(b)
                        #endif
                    }
                } else {
                    representedClass = .image
                    if storeBytes {
                        setBytes(data)
                    }
                }
                return

            } else if let item = obj as? MKMapItem {
                log("      received map item: \(item)")
                await setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 10, .center)
                representedClass = .mapItem
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? URL {
                try await handleUrl(item, data, storeBytes)
                return

            } else if let item = obj as? NSArray {
                log("      received array: \(item)")
                if item.count == 1 {
                    setTitleInfo("1 Item", 1)
                } else {
                    setTitleInfo("\(item.count) Items", 1)
                }
                await setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
                representedClass = .array
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? NSDictionary {
                log("      received dictionary: \(item)")
                if item.count == 1 {
                    setTitleInfo("1 Entry", 1)
                } else {
                    setTitleInfo("\(item.count) Entries", 1)
                }
                await setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
                representedClass = .dictionary
                if storeBytes {
                    setBytes(data)
                }
                return
            }
        }

        log("      not a known class, storing data: \(data)")
        representedClass = .data
        try await handleData(data, resolveUrls: true, storeBytes: storeBytes)
    }

    public func setTitle(from url: URL) {
        if url.isFileURL {
            setTitleInfo(url.lastPathComponent, 6)
        } else {
            setTitleInfo(url.absoluteString, 6)
        }
    }

    func setTitleInfo(_ text: String?, _ priority: Int) {
        let alignment: NSTextAlignment
        let finalText: String?
        if let text, text.count > 200 {
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

    private func getPdfTitle() -> String? {
        if let document = CGPDFDocument(bytesPath as CFURL), let info = document.info {
            var titleStringRef: CGPDFStringRef?
            CGPDFDictionaryGetString(info, "Title", &titleStringRef)
            if let titleStringRef, let s = CGPDFStringCopyTextString(titleStringRef), !(s as String).isEmpty {
                return s as String
            }
        }
        return nil
    }

    private func generatePdfPreview() -> IMAGE? {
        guard let document = CGPDFDocument(bytesPath as CFURL), let firstPage = document.page(at: 1) else { return nil }

        let side: CGFloat = 1024

        var pageRect = firstPage.getBoxRect(.cropBox)
        let pdfScale = min(side / pageRect.size.width, side / pageRect.size.height)
        pageRect.origin = .zero
        pageRect.size.width *= pdfScale
        pageRect.size.height *= pdfScale

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
            #if canImport(AppKit)
                return IMAGE(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            #else
                return IMAGE(cgImage: cgImage, scale: 1, orientation: .up)
            #endif
        } else {
            return nil
        }
    }

    public var previewTempPath: URL {
        let path = temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString, isDirectory: false)
        if isWebURL {
            return path.appendingPathExtension("webloc")
        } else if let f = fileExtension {
            return path.appendingPathExtension(f)
        } else {
            return path
        }
    }

    #if canImport(WatchKit)
        private func generateMoviePreview() async -> IMAGE? {
            nil
        }
    #else
        private func generateMoviePreview() async -> IMAGE? {
            let fm = FileManager.default
            let tempPath = previewTempPath

            defer {
                if tempPath != bytesPath {
                    try? fm.removeItem(at: tempPath)
                }
            }

            do {
                if fm.fileExists(atPath: tempPath.path) {
                    try fm.removeItem(at: tempPath)
                }

                try fm.linkItem(at: bytesPath, to: tempPath)

                let asset = AVURLAsset(url: tempPath, options: nil)
                let imgGenerator = AVAssetImageGenerator(asset: asset)
                imgGenerator.appliesPreferredTrackTransform = true

                #if os(visionOS)
                    let cgImage = try await imgGenerator.image(at: CMTimeMake(value: 0, timescale: 1)).image
                    return UIImage(cgImage: cgImage)
                #elseif canImport(AppKit)
                    let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
                    return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                #elseif canImport(UIKit)
                    let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
                    return UIImage(cgImage: cgImage)
                #endif

            } catch {
                log("Error generating movie thumbnail: \(error.localizedDescription)")
            }

            return nil
        }
    #endif

    public var isText: Bool {
        !typeConforms(to: .vCard) && (typeConforms(to: .text) || isRichText)
    }

    public var isRichText: Bool {
        typeConforms(to: .rtf) || typeConforms(to: .rtfd) || typeConforms(to: .flatRTFD) || typeIdentifier == "com.apple.uikit.attributedstring"
    }

    public var textEncoding: String.Encoding {
        typeConforms(to: .utf16PlainText) ? .utf16 : .utf8
    }

    func handleRemoteUrl(_ url: URL, _: Data, _: Bool) async throws {
        log("      received remote url: \(url.absoluteString)")
        await setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
        guard let s = url.scheme, s.hasPrefix("http") else {
            throw GladysError.blankResponse
        }

        let res = try? await WebArchiver.shared.fetchWebPreview(for: url.absoluteString)
        if flags.contains(.loadingAborted) {
            try await ingestFailed(error: nil)
        }
        accessoryTitle = res?.title ?? accessoryTitle
        if let image = res?.image {
            if image.size.height > 100 || image.size.width > 200 {
                let thumb = res?.isThumbnail ?? false
                await setDisplayIcon(image, 30, thumb ? .fill : .fit)
            } else {
                await setDisplayIcon(image, 30, .center)
            }
        }
    }

    func handleData(_ data: Data, resolveUrls: Bool, storeBytes: Bool) async throws {
        if storeBytes {
            setBytes(data)
        }

        if (typeIdentifier == "public.folder" || typeIdentifier == "public.data") && data.isZip {
            typeIdentifier = "public.zip-archive"
        }

        if let image = await IMAGE.from(data: data) {
            await setDisplayIcon(image, 50, .fill)

        } else if typeIdentifier == "public.vcard" {
            if let contacts = try? CNContactVCardSerialization.contacts(with: data), let person = contacts.first {
                let name = [person.givenName, person.middleName, person.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let job = [person.jobTitle, person.organizationName].filter { !$0.isEmpty }.joined(separator: ", ")
                accessoryTitle = [name, job].filter { !$0.isEmpty }.joined(separator: " - ")

                if let imageData = person.imageData, let img = await IMAGE.from(data: imageData) {
                    await setDisplayIcon(img, 9, .circle)
                } else {
                    await setDisplayIcon(#imageLiteral(resourceName: "iconPerson"), 5, .center)
                }
            }

        } else if typeIdentifier == "public.utf8-plain-text" {
            if let s = String(data: data, encoding: .utf8) {
                setTitleInfo(s, 9)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if typeIdentifier == "public.utf16-plain-text" {
            if let s = String(data: data, encoding: .utf16) {
                setTitleInfo(s, 8)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if typeIdentifier == "public.email-message" {
            await setDisplayIcon(#imageLiteral(resourceName: "iconEmail"), 10, .center)

        } else if typeIdentifier == "com.apple.mapkit.map-item" {
            await setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 5, .center)

        } else if typeIdentifier.hasSuffix(".rtf") || typeIdentifier.hasSuffix(".rtfd") || typeIdentifier.hasSuffix(".flat-rtfd") {
            if let data = (decode() as? Data), let s = (try? NSAttributedString(data: data, options: [:], documentAttributes: nil))?.string {
                setTitleInfo(s, 4)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if resolveUrls, let url = encodedUrl {
            try await handleUrl(url as URL, data, storeBytes)
            return // important

        } else if typeConforms(to: .text) {
            if let s = String(data: data, encoding: .utf8) {
                setTitleInfo(s, 5)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if typeConforms(to: .image) {
            await setDisplayIcon(#imageLiteral(resourceName: "image"), 5, .center)

        } else if typeConforms(to: .audiovisualContent) {
            if let moviePreview = await generateMoviePreview() {
                await setDisplayIcon(moviePreview, 50, .fill)
            } else {
                await setDisplayIcon(#imageLiteral(resourceName: "movie"), 30, .center)
            }

        } else if typeConforms(to: .audio) {
            await setDisplayIcon(#imageLiteral(resourceName: "audio"), 30, .center)

        } else if typeConforms(to: .pdf), let pdfPreview = generatePdfPreview() {
            if let title = getPdfTitle(), !title.isEmpty {
                setTitleInfo(title, 11)
            }
            await setDisplayIcon(pdfPreview, 50, .fill)

        } else if typeConforms(to: .content) {
            await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)

        } else if typeConforms(to: .archive) {
            await setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)

        } else {
            await setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
        }
    }

    func reIngest() async throws {
        if let bytes {
            try await ingest(data: bytes, storeBytes: false)
        }
    }

    private func setDisplayIcon(_ icon: IMAGE, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) async {
        guard priority >= displayIconPriority else {
            return
        }

        componentIcon = await Task.detached(priority: .userInitiated) {
            switch contentMode {
            case .fit:
                icon.limited(to: Component.iconPointSize, limitTo: 0.75, useScreenScale: true)
            case .fill:
                icon.limited(to: Component.iconPointSize, useScreenScale: true)
            case .center, .circle:
                icon
            }
        }.value

        displayIconPriority = priority
        displayIconContentMode = contentMode
        #if canImport(AppKit)
            displayIconTemplate = icon.isTemplate
        #else
            displayIconTemplate = icon.renderingMode == .alwaysTemplate
        #endif
    }

    #if canImport(AppKit)
        func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool) async throws {
            setTitle(from: url)

            if url.isFileURL {
                try await handleFileUrl(url, data, storeBytes)

            } else {
                if storeBytes {
                    setBytes(data)
                }
                representedClass = .url
                try await handleRemoteUrl(url, data, storeBytes)
            }
        }

        private func handleFileUrl(_ item: URL, _ data: Data, _ storeBytes: Bool) async throws {
            if PersistedOptions.readAndStoreFinderTagsAsLabels {
                let resourceValues = try? item.resourceValues(forKeys: [.tagNamesKey])
                contributedLabels = resourceValues?.tagNames
            } else {
                contributedLabels = nil
            }

            accessoryTitle = item.lastPathComponent
            let fm = FileManager.default
            var directory: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &directory) else {
                if storeBytes {
                    setBytes(data)
                }
                representedClass = .url
                log("      received local file url for non-existent file: \(item.absoluteString)")
                await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
                return
            }

            if directory.boolValue {
                do {
                    typeIdentifier = UTType.zip.identifier
                    await setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)
                    representedClass = .data
                    let tempURL = temporaryDirectoryUrl.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
                    let a = Archive(url: tempURL, accessMode: .create)!
                    let dirName = item.lastPathComponent
                    let item = item.deletingLastPathComponent()
                    try appendDirectory(item, chain: [dirName], archive: a, fm: fm)
                    if flags.contains(.loadingAborted) {
                        log("      Cancelled zip operation since ingest was aborted")
                        return
                    }
                    try fm.moveAndReplaceItem(at: tempURL, to: bytesPath)
                    log("      zipped files at url: \(item.absoluteString)")
                } catch {
                    if storeBytes {
                        setBytes(data)
                    }
                    representedClass = .url
                    log("      could not read data from file (\(error.localizedDescription)) treating as local file url: \(item.absoluteString)")
                    await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
                }

            } else {
                let ext = item.pathExtension
                if !ext.isEmpty, let uti = UTType(filenameExtension: ext) {
                    typeIdentifier = uti.identifier
                } else {
                    typeIdentifier = UTType.data.identifier
                }
                representedClass = .data
                log("      read data from file url: \(item.absoluteString) - type assumed to be \(typeIdentifier)")
                let data = Data.forceMemoryMapped(contentsOf: item) ?? Data()
                try await handleData(data, resolveUrls: false, storeBytes: storeBytes)
            }
        }

        private func appendDirectory(_ baseURL: URL, chain: [String], archive: Archive, fm: FileManager) throws {
            let joinedChain = chain.joined(separator: "/")
            let dirURL = baseURL.appendingPathComponent(joinedChain)
            for file in try fm.contentsOfDirectory(atPath: dirURL.path) {
                if flags.contains(.loadingAborted) {
                    log("      Interrupted zip operation since ingest was aborted")
                    break
                }
                let newURL = dirURL.appendingPathComponent(file)
                var directory: ObjCBool = false
                if fm.fileExists(atPath: newURL.path, isDirectory: &directory) {
                    if directory.boolValue {
                        var newChain = chain
                        newChain.append(file)
                        try appendDirectory(baseURL, chain: newChain, archive: archive, fm: fm)
                    } else {
                        log("      Compressing \(newURL.path)")
                        let path = joinedChain + "/" + file
                        try archive.addEntry(with: path, relativeTo: baseURL)
                    }
                }
            }
        }

    #else
        func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool) async throws {
            if storeBytes {
                setBytes(data)
            }
            representedClass = .url
            setTitle(from: url)

            if url.isFileURL {
                log("      received local file url: \(url.path)")
                await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
            } else {
                try await handleRemoteUrl(url, data, storeBytes)
            }
        }
    #endif

    @MainActor
    public var parent: ArchivedItem? {
        DropStore.item(uuid: parentUuid)
    }

    @MainActor
    public func markComponentUpdated() {
        updatedAt = Date()
        parent?.needsReIngest = true
    }

    @MainActor
    public var parentZone: CKRecordZone.ID {
        parent?.parentZone ?? privateZoneId
    }

    @MainActor
    public var populatedCloudKitRecord: CKRecord? {
        let record = cloudKitRecord
            ?? CKRecord(recordType: "ArchivedDropItemType",
                        recordID: CKRecord.ID(recordName: uuid.uuidString, zoneID: parentZone))

        let parentId = CKRecord.ID(recordName: parentUuid.uuidString, zoneID: record.recordID.zoneID)
        record.parent = CKRecord.Reference(recordID: parentId, action: .none)
        record.setValuesForKeys([
            "parent": CKRecord.Reference(recordID: parentId, action: .deleteSelf),
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "typeIdentifier": typeIdentifier,
            "representedClass": representedClass.name,
            "classWasWrapped": classWasWrapped ? 1 : 0,
            "order": order
        ])

        record["accessoryTitle"] = accessoryTitle
        record["bytes"] = hasBytes ? CKAsset(fileURL: bytesPath) : nil
        return record
    }

    public func cloudKitUpdate(from record: CKRecord) {
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
    }

    @MainActor
    public var dataForDropping: Data? {
        if classWasWrapped, typeIdentifier.hasPrefix("public.") {
            let decoded = decode()
            if let s = decoded as? String {
                return Data(s.utf8)
            } else if let s = decoded as? NSAttributedString {
                return s.toData
            } else if let s = decoded as? URL {
                let urlString = s.absoluteString
                let list = [urlString, "", ["title": urlDropTitle]] as [Any]
                return try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
            }
        }
        if !classWasWrapped, typeIdentifier == "public.url", let s = encodedUrl {
            let urlString = s.absoluteString
            let list = [urlString, "", ["title": urlDropTitle]] as [Any]
            return try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
        }
        return nil
    }

    @MainActor
    private var urlDropTitle: String {
        parent?.trimmedSuggestedName ?? oneTitle
    }
}
