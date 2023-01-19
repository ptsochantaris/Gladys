import Foundation

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

public extension Error {
    var finalDescription: String {
        let err = self as NSError
        return (err.userInfo[NSUnderlyingErrorKey] as? NSError)?.finalDescription ?? err.localizedDescription
    }
}

public extension String {
    var filenameSafe: String {
        if let components = URLComponents(string: self) {
            if let host = components.host {
                return host + "-" + components.path.split(separator: "/").joined(separator: "-")
            } else {
                return components.path.split(separator: "/").joined(separator: "-")
            }
        } else {
            return replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "/", with: "-")
        }
    }

    var dropFilenameSafe: String {
        if let components = URLComponents(string: self) {
            if let host = components.host {
                return host + "-" + components.path.split(separator: "/").joined(separator: "-")
            } else {
                return components.path.split(separator: "/").joined(separator: "-")
            }
        } else {
            return replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        }
    }
}

public extension URL {
    var urlFileContent: Data {
        Data("[InternetShortcut]\r\nURL=\(absoluteString)\r\n".utf8)
    }
}

public enum RepresentedClass: Codable, Equatable {
    public init(from decoder: Decoder) throws {
        self.init(name: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .data: try container.encode("NSData")
        case .string: try container.encode("NSString")
        case .attributedString: try container.encode("NSAttributedString")
        case .color: try container.encode("UIColor")
        case .image: try container.encode("UIImage")
        case .mapItem: try container.encode("MKMapItem")
        case .array: try container.encode("NSArray")
        case .dictionary: try container.encode("NSDictionary")
        case .url: try container.encode("URL")
        case let .unknown(name: value):
            try container.encode(value)
        }
    }

    case data, string, attributedString, color, image, mapItem, array, dictionary, url, unknown(name: String)

    public init(name: String) {
        switch name {
        case "NSData": self = .data
        case "NSString": self = .string
        case "NSAttributedString": self = .attributedString
        case "UIColor": self = .color
        case "UIImage": self = .image
        case "MKMapItem": self = .mapItem
        case "NSArray": self = .array
        case "NSDictionary": self = .dictionary
        case "URL": self = .url
        default: self = .unknown(name: name)
        }
    }

    public var name: String {
        switch self {
        case .data: return "NSData"
        case .string: return "NSString"
        case .attributedString: return "NSAttributedString"
        case .color: return "UIColor"
        case .image: return "UIImage"
        case .mapItem: return "MKMapItem"
        case .array: return "NSArray"
        case .dictionary: return "NSDictionary"
        case .url: return "URL"
        case let .unknown(name: value): return value
        }
    }

    public var description: String {
        switch self {
        case .data: return "Data"
        case .string: return "Text"
        case .attributedString: return "Rich Text"
        case .color: return "Color"
        case .image: return "Image"
        case .mapItem: return "Map Location"
        case .array: return "List"
        case .dictionary: return "Associative List"
        case .url: return "Link"
        case let .unknown(name: value): return "Other (\(value))"
        }
    }

    public static func == (lhs: RepresentedClass, rhs: RepresentedClass) -> Bool {
        lhs.name == rhs.name
    }
}
