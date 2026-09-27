import Foundation
import GladysCommon
import WidgetKit

nonisolated struct CurrentState: TimelineEntry {
    let date: Date
    let displaySize: CGSize
    let items: [PresentationInfo]
}
