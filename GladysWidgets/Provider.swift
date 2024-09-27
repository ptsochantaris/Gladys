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
        await CurrentState(date: Date(), displaySize: context.displaySize, items: loadPresentationInfo(in: context, configuration: configuration))
    }

    func timeline(for configuration: ConfigIntent, in context: Context) async -> Timeline<CurrentState> {
        let entry = await CurrentState(date: Date(), displaySize: context.displaySize, items: loadPresentationInfo(in: context, configuration: configuration))
        return Timeline(entries: [entry], policy: .never)
    }

    private func loadPresentationInfo(in context: Context, configuration: ConfigIntent) async -> [PresentationInfo] {
        let itemCount = context.family.maxCount - 1

        return await Task { @MainActor in
            let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))

            let search = configuration.search ?? ""
            if search.isPopulated {
                filter.text = search
            }

            let labelFilterId = configuration.label?.id ?? ""
            if labelFilterId.isPopulated {
                filter.enableLabelsByName([labelFilterId])
            }
            filter.update(signalUpdate: .none)

            let drops = filter.filteredDrops.prefix(itemCount)
            return await drops.asyncCompactMap {
                await $0.createPresentationInfo(style: .widget, expectedSize: .zero, alwaysStartFresh: true)
            }
        }.value
    }
}
