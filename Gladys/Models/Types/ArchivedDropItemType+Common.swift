
//
//  File.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import CloudKit
import SafeUnarchiver
#if os(iOS)
import MobileCoreServices
#endif
import GladysFramework

extension ArchivedDropItemType: Equatable {

	func setBytes(_ data: Data?) {
        let byteLocation = bytesPath
		dataAccessQueue.async {
			if data == nil || self.loadingAborted {
				let f = FileManager.default
                let path = byteLocation.path
				if f.fileExists(atPath: path) {
					try? f.removeItem(atPath: path)
				}
			} else {
				try? data?.write(to: byteLocation)
				#if os(OSX)
				lastGladysBlobUpdate = Date()
				#endif
			}
		}
	}

	static func == (lhs: ArchivedDropItemType, rhs: ArchivedDropItemType) -> Bool {
		return lhs.uuid == rhs.uuid
	}

	var filenameTypeIdentifier: String {
		return typeIdentifier.replacingOccurrences(of: ".", with: "-")
	}

	var oneTitle: String {
		return accessoryTitle ?? displayTitle ?? filenameTypeIdentifier
	}

	func markUpdated() {
		updatedAt = Date()
	}

	func decode() -> Any? {
		guard let bytes = bytes else { return nil }

		// Do not do this because there may be a URL hidden there
		//if representedClass == "NSData" {
		//return bytes
		//}

		if classWasWrapped {
			return SafeUnarchiver.unarchive(bytes)
		} else if isPlist, let propertyList = (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) {
			return propertyList
		} else {
			return bytes
		}
	}

	var bytes: Data? {
		var data: Data?
		dataAccessQueue.sync {
			let byteLocation = bytesPath
			if FileManager.default.fileExists(atPath: byteLocation.path) {
				data = try? Data(contentsOf: byteLocation, options: [.mappedIfSafe])
			}
		}
		return data
	}
    
    var hasBytes: Bool {
        var exists = false
        dataAccessQueue.sync {
            exists = FileManager.default.fileExists(atPath: bytesPath.path)
        }
        return exists
    }
    
    var isPlist: Bool {
        return bytes?.isPlist ?? false
    }

	var encodedUrl: NSURL? {

		if let encodedURLCache = encodedURLCache {
			return encodedURLCache.1
		}

		var ret: NSURL?
		if isURL {
			let decoded = decode()
			if let u = decoded as? NSURL {
				ret = u
			} else if let array = decoded as? NSArray {
				for item in array {
					if let text = item as? String, let url = NSURL(string: text), let scheme = url.scheme, !scheme.isEmpty {
						ret = url
						break
					}
				}
			} else if let d = decoded as? Data, let s = String(bytes: d, encoding: .utf8), let u = NSURL(string: s) {
				ret = u
			}
		}

		encodedURLCache = (true, ret)
		return ret
	}

	var fileExtension: String? {
		let tag = UTTypeCopyPreferredTagWithClass(typeIdentifier as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue()
		if let tag = tag {
			let t = tag as String
			if !t.isEmpty {
				return t
			}
		}
		if isURL {
			return "url"
		}
		if typeIdentifier.hasSuffix("-plain-text") {
			return "txt"
		}
		return nil
	}

	var isURL: Bool {
		return typeConforms(to: kUTTypeURL)
	}

	var isWebURL: Bool {
		if let e = encodedUrl {
			return e.scheme != "file"
		}
		return false
	}

	var isFileURL: Bool {
		if let e = encodedUrl {
			return e.scheme == "file"
		}
		return false
	}

	var isWebArchive: Bool {
		return typeIdentifier == "com.apple.webarchive"
	}

	var typeDescription: String {

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

		return representedClass.description
	}

	func typeConforms(to parent: CFString) -> Bool {
		return UTTypeConformsTo(typeIdentifier as CFString, parent)
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

	var folderUrl: URL {
		let nsuuiud = uuid as NSUUID
		if let url = folderUrlCache.object(forKey: nsuuiud) {
			return url as URL
		}

		let url = Model.appStorageUrl.appendingPathComponent(parentUuid.uuidString).appendingPathComponent(uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		folderUrlCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}

	var imagePath: URL {
		let nsuuiud = uuid as NSUUID
		if let url = imagePathCache.object(forKey: nsuuiud) {
			return url as URL
		}

		let url = folderUrl.appendingPathComponent("thumbnail.png")
		imagePathCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}

	var bytesPath: URL {
		let nsuuiud = uuid as NSUUID
		if let url = bytesPathCache.object(forKey: nsuuiud) {
			return url as URL
		}

		let url = folderUrl.appendingPathComponent("blob", isDirectory: false)
		bytesPathCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}
	
	private var cloudKitDataPath: URL {
		let nsuuiud = uuid as NSUUID
		if let url = cloudKitDataPathCache.object(forKey: nsuuiud) {
			return url as URL
		}

		let url = folderUrl.appendingPathComponent("ck-record", isDirectory: false)
		cloudKitDataPathCache.setObject(url as NSURL, forKey: nsuuiud)
		return url
	}

	var cloudKitRecord: CKRecord? {
		get {
            return dataAccessQueue.sync {
                let nsuuid = uuid as NSUUID
                if let cachedValue = cloudKitRecordCache.object(forKey: nsuuid) {
                    return cachedValue.record
                }

                let recordLocation = cloudKitDataPath
                let record: CKRecord?
                if FileManager.default.fileExists(atPath: recordLocation.path) {
                    let data = try! Data(contentsOf: recordLocation, options: [])
                    let coder = try! NSKeyedUnarchiver(forReadingFrom: data)
                    record = CKRecord(coder: coder)
                    coder.finishDecoding()
                } else {
                    record = nil
                }
                cloudKitRecordCache.setObject(CKRecordCacheEntry(record: record), forKey: nsuuid)
                return record
            }
		}
		set {
            let nsuuid = uuid as NSUUID
            let recordLocation = cloudKitDataPath
            dataAccessQueue.async {
                if let newValue = newValue {
                    cloudKitRecordCache.setObject(CKRecordCacheEntry(record: newValue), forKey: nsuuid)
                    let coder = NSKeyedArchiver(requiringSecureCoding: true)
                    newValue.encodeSystemFields(with: coder)
                    try? coder.encodedData.write(to: recordLocation, options: .atomic)
                } else {
                    cloudKitRecordCache.setObject(CKRecordCacheEntry(record: nil), forKey: nsuuid)
                    let f = FileManager.default
                    if f.fileExists(atPath: recordLocation.path) {
                        try? f.removeItem(at: recordLocation)
                    }
                }
            }
		}
	}

	func clearCachedFields() {
		encodedURLCache = nil
		canPreviewCache = nil
	}

	var parent: ArchivedDropItem? {
		return Model.item(uuid: parentUuid)
	}
}
