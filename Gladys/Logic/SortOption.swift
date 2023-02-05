import CloudKit
import CoreSpotlight
import GladysCommon
import GladysUI
import Intents
import MapKit
import UIKit

extension Model.SortOption {
    var ascendingIcon: UIImage? {
        switch self {
        case .label: return UIImage(systemName: "line.horizontal.3")
        case .dateAdded: return UIImage(systemName: "calendar")
        case .dateModified: return UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: return UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: return UIImage(systemName: "arrow.down")
        case .size: return UIImage(systemName: "arrow.up.left.and.arrow.down.right.circle")
        }
    }

    var descendingIcon: UIImage? {
        switch self {
        case .label: return UIImage(systemName: "line.horizontal.3")
        case .dateAdded: return UIImage(systemName: "calendar")
        case .dateModified: return UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: return UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: return UIImage(systemName: "arrow.up")
        case .size: return UIImage(systemName: "arrow.down.forward.and.arrow.up.backward.circle")
        }
    }
}
