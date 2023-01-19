import Foundation

public enum ItemColor: String, CaseIterable, Codable {
    case none, blue, red, purple, green, cyan, yellow, gray

    public var title: String {
        switch self {
        case .green: return "Green"
        case .red: return "Red"
        case .blue: return "Blue"
        case .cyan: return "Cyan"
        case .gray: return "Gray"
        case .none: return "None"
        case .purple: return "Purple"
        case .yellow: return "Yellow"
        }
    }

    public var color: COLOR {
        switch self {
        case .green: return COLOR.green
        case .red: return COLOR.red
        case .blue: return COLOR.blue
        case .cyan: return COLOR.cyan
        case .gray: return COLOR.gray
        case .none: return COLOR.g_colorMacCard
        case .purple: return COLOR.purple
        case .yellow: return COLOR.yellow
        }
    }

    public var invertText: Bool {
        switch self {
        case .cyan: return true
        case .none: return false
        case .yellow: return false
        case .purple: return true
        case .gray: return true
        case .blue: return true
        case .red: return true
        case .green: return true
        }
    }

    public var img: IMAGE? {
        switch self {
        case .none: return IMAGE(systemName: "circle")
        default: return IMAGE.tintedShape(systemName: "circle.fill", coloured: color)
        }
    }
}
