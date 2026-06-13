import Foundation
import GladysCommon
import WidgetKit

struct CurrentState: TimelineEntry {
    let date: Date
    let displaySize: CGSize
    let items: [PresentationInfo]
}
