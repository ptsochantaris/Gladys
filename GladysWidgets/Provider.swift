import Foundation
import GladysCommon
import GladysUI
import Lista
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CurrentState {
        let itemCount = maxCount(in: context)
        return CurrentState(date: Date(), displaySize: context.displaySize, items: PresentationInfo.placeholders(count: itemCount))
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> CurrentState {
        await CurrentState(date: Date(), displaySize: context.displaySize, items: loadPresentationInfo(in: context, configuration: configuration))
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<CurrentState> {
        let entry = await CurrentState(date: Date(), displaySize: context.displaySize, items: loadPresentationInfo(in: context, configuration: configuration))
        return Timeline(entries: [entry], policy: .never)
    }

    private func maxCount(in context: Context) -> Int {
        switch context.family {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 4
        case .systemMedium: 8
        case .systemLarge: 16
        case .systemExtraLarge: 32
        @unknown default: 1
        }
    }

    private func loadPresentationInfo(in context: Context, configuration: ConfigurationAppIntent) async -> [PresentationInfo] {
        let itemCount = maxCount(in: context) - 1

        let drops = await Task { @MainActor in
            let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))
            if let search = configuration.search, search.isPopulated {
                filter.text = search
            }
            if let labelFilter = configuration.label?.id, labelFilter.isPopulated {
                filter.enableLabelsByName([labelFilter])
            }
            filter.update(signalUpdate: .none)
            return filter.filteredDrops.prefix(itemCount)
        }.value

        var res = [PresentationInfo]()
        res.reserveCapacity(drops.count)
        for drop in drops {
            if let info = await drop.createPresentationInfo(style: .widget) {
                res.append(info)
            }
        }
        return res
    }
}
