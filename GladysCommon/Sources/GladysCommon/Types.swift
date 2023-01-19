import Foundation

#if os(macOS)
    import Cocoa
    public typealias IMAGE = NSImage
    public typealias COLOR = NSColor
    public let groupName = "X727JSJUGJ.build.bru.MacGladys"
#else
    import UIKit
    public typealias IMAGE = UIImage
    public typealias COLOR = UIColor
    public let groupName = "group.build.bru.Gladys"
#endif

public let GladysFileUTI = "build.bru.gladys.archive"

public let kGladysStartSearchShortcutActivity = "build.bru.Gladys.shortcut.search"
public let kGladysStartPasteShortcutActivity = "build.bru.Gladys.shortcut.paste"
public let kGladysMainListActivity = "build.bru.Gladys.main.list"
public let kGladysDetailViewingActivity = "build.bru.Gladys.item.view"
public let kGladysQuicklookActivity = "build.bru.Gladys.item.quicklook"
public let kGladysDetailViewingActivityItemUuid = "kGladysDetailViewingActivityItemUuid"
public let kGladysDetailViewingActivityItemTypeUuid = "kGladysDetailViewingActivityItemTypeUuid"
public let kGladysMainViewSearchText = "kGladysMainViewSearchText"
public let kGladysMainViewDisplayMode = "kGladysMainViewDisplayMode"
public let kGladysMainViewSections = "kGladysMainViewSections"
public let kGladysMainFilter = "mainFilter"

public let itemAccessQueue = DispatchQueue(label: "build.bru.Gladys.itemAccessQueue", qos: .default, attributes: .concurrent)
public let componentAccessQueue = DispatchQueue(label: "build.bru.Gladys.componentAccessQueue", qos: .default, attributes: .concurrent)

public enum ArchivedDropItemDisplayType: Int {
    case fit, fill, center, circle
}
