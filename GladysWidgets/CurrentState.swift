import Foundation
import GladysCommon
import WidgetKit

struct CurrentState: TimelineEntry, Sendable {
    let date: Date
    let displaySize: CGSize
    let items: [PresentationInfo]
}
