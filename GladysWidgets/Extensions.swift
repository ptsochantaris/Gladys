import Foundation
import WidgetKit

extension WidgetFamily {
    var colunms: CGFloat {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 2
        case .systemMedium: 4
        case .systemLarge: 4
        case .systemExtraLarge: 8
        case .systemExtraLargePortrait: 4
        @unknown default: 1
        }
    }

    var rows: CGFloat {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 2
        case .systemMedium: 2
        case .systemLarge: 4
        case .systemExtraLarge: 4
        case .systemExtraLargePortrait: 8
        @unknown default: 1
        }
    }

    var maxCount: Int {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 4
        case .systemMedium: 8
        case .systemLarge: 16
        case .systemExtraLarge, .systemExtraLargePortrait: 32
        @unknown default: 1
        }
    }
}
