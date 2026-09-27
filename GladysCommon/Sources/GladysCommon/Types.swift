import CloudKit
import Foundation
import SwiftUI

#if canImport(AppKit)
    import AppKit

    public typealias IMAGE = NSImage
    public typealias COLOR = NSColor
    public typealias VIEWCLASS = NSView
    public typealias VRCLASS = NSViewRepresentable
    public typealias FONT = NSFont
    public nonisolated let groupName = "X727JSJUGJ.build.bru.MacGladys"

#elseif canImport(UIKit)
    import UIKit

    public typealias IMAGE = UIImage
    public typealias COLOR = UIColor
    #if !os(watchOS)
        public typealias VIEWCLASS = UIView
        public typealias VRCLASS = UIViewRepresentable
    #endif
    public typealias FONT = UIFont
    public nonisolated let groupName = "group.build.bru.Gladys"
#endif

#if os(visionOS)
    public nonisolated let cellCornerRadius: CGFloat = 36
#else
    public nonisolated let cellCornerRadius: CGFloat = 18
#endif

public nonisolated let GladysFileUTI = "build.bru.gladys.archive"

public nonisolated let kGladysStartSearchShortcutActivity = "build.bru.Gladys.shortcut.search"
public nonisolated let kGladysStartPasteShortcutActivity = "build.bru.Gladys.shortcut.paste"
public nonisolated let kGladysMainListActivity = "build.bru.Gladys.main.list"
public nonisolated let kGladysDetailViewingActivity = "build.bru.Gladys.item.view"
public nonisolated let kGladysQuicklookActivity = "build.bru.Gladys.item.quicklook"
public nonisolated let kGladysDetailViewingActivityItemUuid = "kGladysDetailViewingActivityItemUuid"
public nonisolated let kGladysDetailViewingActivityItemTypeUuid = "kGladysDetailViewingActivityItemTypeUuid"
public nonisolated let kGladysMainViewSearchText = "kGladysMainViewSearchText"
public nonisolated let kGladysMainViewDisplayMode = "kGladysMainViewDisplayMode"
public nonisolated let kGladysMainViewSections = "kGladysMainViewSections"
public nonisolated let kGladysMainFilter = "mainFilter"

public nonisolated enum ArchivedDropItemDisplayType: Int, Sendable {
    case fit, fill, center, circle

    public var prefersFullSizeImage: Bool {
        switch self {
        case .circle, .fill, .fit:
            true
        case .center:
            false
        }
    }
}

public nonisolated let privateZoneId = CKRecordZone.ID(zoneName: "archivedDropItems", ownerName: CKCurrentUserDefaultName)

public nonisolated let itemsDirectoryUrl: URL = appStorageUrl.appendingPathComponent("items", isDirectory: true)

public nonisolated enum PasteResult: Sendable {
    case success([ArchivedItem]), noData
}

public nonisolated func modificationDate(for url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

public nonisolated let appStorageUrl: URL = {
    #if canImport(AppKit)
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
    #else
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!.appendingPathComponent("File Provider Storage")
    #endif
    log("Model URL: \(url.path)")
    return url
}()

public nonisolated let temporaryDirectoryUrl: URL = {
    let url = appStorageUrl.appendingPathComponent("temporary", isDirectory: true)
    let fm = FileManager.default
    let p = url.path
    if fm.fileExists(atPath: p) {
        try? fm.removeItem(atPath: p)
    }
    try! fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}()

public nonisolated let loadDecoder: JSONDecoder = {
    log("Creating new loading decoder")
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
    return decoder
}()

public nonisolated let saveEncoder: JSONEncoder = {
    log("Creating new saving encoder")
    let encoder = JSONEncoder()
    encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "pi", negativeInfinity: "ni", nan: "nan")
    return encoder
}()
