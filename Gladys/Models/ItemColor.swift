import Foundation

enum ItemColor: String, CaseIterable, Codable {
    case none, blue, red, purple, green, cyan, yellow, gray
    
    var title: String {
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
    
    var color: COLOR {
        switch self {
        case .green: return COLOR.systemGreen
        case .red: return COLOR.systemRed
        case .blue: return COLOR.systemBlue
        case .cyan: return COLOR.systemCyan
        case .gray: return COLOR.systemGray
        case .none: return COLOR.g_colorMacCard
        case .purple: return COLOR.systemPurple
        case .yellow: return COLOR.systemYellow
        }
    }
    
    var invertText: Bool {
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
    
    var img: IMAGE? {
        switch self {
        case .none: return IMAGE(systemName: "circle")
        default: return IMAGE.tintedShape(systemName: "circle.fill", coloured: color)
        }
    }
}
