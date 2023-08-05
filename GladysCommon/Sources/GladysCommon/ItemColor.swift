public enum ItemColor: String, CaseIterable, Codable {
    case none, blue, red, purple, green, cyan, yellow, gray

    public var title: String {
        switch self {
        case .green: "Green"
        case .red: "Red"
        case .blue: "Blue"
        case .cyan: "Cyan"
        case .gray: "Gray"
        case .none: "None"
        case .purple: "Purple"
        case .yellow: "Yellow"
        }
    }

    #if !os(watchOS)
        public var bgColor: COLOR {
            switch self {
            case .green: COLOR.systemGreen
            case .red: COLOR.systemRed
            case .blue: COLOR.systemBlue
            case .cyan: COLOR.systemCyan
            case .gray: COLOR.systemGray
            case .none: COLOR.g_colorMacCard
            case .purple: COLOR.systemPurple
            case .yellow: COLOR.systemYellow
            }
        }
    #endif

    public var fgColor: COLOR {
        switch self {
        case .green: COLOR.black
        case .red: COLOR.white
        case .blue: COLOR.white
        case .cyan: COLOR.black
        case .gray: COLOR.g_colorComponentLabelInverse
        case .none: COLOR.g_colorComponentLabel
        case .purple: COLOR.white
        case .yellow: COLOR.black
        }
    }

    public var tintColor: COLOR {
        switch self {
        case .none: COLOR.g_colorTint
        default: fgColor
        }
    }

    #if !os(watchOS)
        public var img: IMAGE? {
            switch self {
            case .none:
                IMAGE(systemName: "circle")
            default:
                IMAGE.tintedShape(systemName: "circle.fill", coloured: bgColor)
            }
        }
    #endif
}
