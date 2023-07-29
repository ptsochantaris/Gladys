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

    public var color: COLOR {
        switch self {
        case .green: COLOR.green
        case .red: COLOR.red
        case .blue: COLOR.blue
        case .cyan: COLOR.cyan
        case .gray: COLOR.gray
        case .none: COLOR.g_colorMacCard
        case .purple: COLOR.purple
        case .yellow: COLOR.yellow
        }
    }

    public var invertText: Bool {
        switch self {
        case .cyan: true
        case .none: false
        case .yellow: false
        case .purple: true
        case .gray: true
        case .blue: true
        case .red: true
        case .green: true
        }
    }

    #if !os(watchOS)
        public var img: IMAGE? {
            switch self {
            case .none:
                IMAGE(systemName: "circle")
            default:
                IMAGE.tintedShape(systemName: "circle.fill", coloured: color)
            }
        }
    #endif
}
