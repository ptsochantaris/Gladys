import Foundation
import GladysCommon
import GladysUI
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CurrentState {
        let itemCount = context.family.maxCount - 1
        let placeholders = onlyOnMainThread { PresentationInfo.placeholders(count: itemCount) }
        return CurrentState(date: Date(), displaySize: context.displaySize, items: placeholders)
    }

    func snapshot(for configuration: ConfigIntent, in context: Context) async -> CurrentState {
        let itemCount = context.family.maxCount - 1

        let info = await Task { @MainActor in
            let allItems = await LiteModel.allItems()
            let filter = Filter(manualDropSource: allItems)

            if let search = configuration.search, search.isPopulated {
                filter.text = search
            }
            if let labelFilterId = configuration.label?.id, labelFilterId.isPopulated {
                filter.enableLabelsByName([labelFilterId])
            }
            filter.update(signalUpdate: .none)

            let drops = filter.filteredDrops.prefix(itemCount)
            return await drops.asyncCompactMap {
                await $0.createPresentationInfo(style: .widget, cellSize: .zero)
            }
        }.value

        return CurrentState(date: Date(), displaySize: context.displaySize, items: info)
    }

    func timeline(for configuration: ConfigIntent, in context: Context) async -> Timeline<CurrentState> {
        let entry = await snapshot(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .never)
    }
}
