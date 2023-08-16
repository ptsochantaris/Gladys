public enum RepresentedClass: Codable, Equatable {
    public init(from decoder: Decoder) throws {
        try self.init(name: decoder.singleValueContainer().decode(String.self))
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
        case .data: "NSData"
        case .string: "NSString"
        case .attributedString: "NSAttributedString"
        case .color: "UIColor"
        case .image: "UIImage"
        case .mapItem: "MKMapItem"
        case .array: "NSArray"
        case .dictionary: "NSDictionary"
        case .url: "URL"
        case let .unknown(name: value): value
        }
    }

    public var description: String {
        switch self {
        case .data: "Data"
        case .string: "Text"
        case .attributedString: "Rich Text"
        case .color: "Color"
        case .image: "Image"
        case .mapItem: "Map Location"
        case .array: "List"
        case .dictionary: "Associative List"
        case .url: "Link"
        case let .unknown(name: value): "Other (\(value))"
        }
    }

    public static func == (lhs: RepresentedClass, rhs: RepresentedClass) -> Bool {
        lhs.name == rhs.name
    }
}
