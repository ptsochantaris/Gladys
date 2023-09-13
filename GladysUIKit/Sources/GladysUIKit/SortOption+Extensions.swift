import GladysCommon
import GladysUI
import UIKit

public extension SortOption {
    var ascendingIcon: UIImage? {
        switch self {
        case .label: UIImage(systemName: "line.horizontal.3")
        case .dateAdded: UIImage(systemName: "calendar")
        case .dateModified: UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: UIImage(systemName: "arrow.down")
        case .size: UIImage(systemName: "arrow.up.left.and.arrow.down.right.circle")
        }
    }

    var descendingIcon: UIImage? {
        switch self {
        case .label: UIImage(systemName: "line.horizontal.3")
        case .dateAdded: UIImage(systemName: "calendar")
        case .dateModified: UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: UIImage(systemName: "arrow.up")
        case .size: UIImage(systemName: "arrow.down.forward.and.arrow.up.backward.circle")
        }
    }
}
