import Foundation

#if MAINAPP
    let kGladysStartSearchShortcutActivity = "build.bru.Gladys.shortcut.search"
#endif

#if MAINAPP || INTENTSEXTENSION
    let kGladysStartPasteShortcutActivity = "build.bru.Gladys.shortcut.paste"
#endif

#if MAINAPP || ACTIONEXTENSION
    let kGladysMainListActivity = "build.bru.Gladys.main.list"
#endif

#if MAINAPP || MAC
    let kGladysDetailViewingActivity = "build.bru.Gladys.item.view"
    let kGladysQuicklookActivity = "build.bru.Gladys.item.quicklook"
    let kGladysDetailViewingActivityItemUuid = "kGladysDetailViewingActivityItemUuid"
    let kGladysDetailViewingActivityItemTypeUuid = "kGladysDetailViewingActivityItemTypeUuid"
    let kGladysMainViewSearchText = "kGladysMainViewSearchText"
    let kGladysMainViewDisplayMode = "kGladysMainViewDisplayMode"
    let kGladysMainViewSections = "kGladysMainViewSections"
    let kGladysMainFilter = "mainFilter"
#endif

enum ArchivedDropItemDisplayType: Int {
    case fit, fill, center, circle
}

extension Error {
    var finalDescription: String {
        let err = self as NSError
        return (err.userInfo[NSUnderlyingErrorKey] as? NSError)?.finalDescription ?? err.localizedDescription
    }
}

extension String {
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

extension URL {
    var urlFileContent: Data {
        Data("[InternetShortcut]\r\nURL=\(absoluteString)\r\n".utf8)
    }
}

enum RepresentedClass: Codable, Equatable {
    init(from decoder: Decoder) throws {
        self.init(name: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
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

    init(name: String) {
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

    var name: String {
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

    var description: String {
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

    static func == (lhs: RepresentedClass, rhs: RepresentedClass) -> Bool {
        lhs.name == rhs.name
    }
}

let dataAccessQueue = DispatchQueue(label: "build.bru.Gladys.dataAccessQueue", qos: .default, attributes: .concurrent)
