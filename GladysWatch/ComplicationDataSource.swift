import ClockKit

final class ComplicationDataSource: NSObject, CLKComplicationDataSource {
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        handler([CLKComplicationDescriptor(identifier: "GladysItemCount",
                                           displayName: "Gladys Item Count",
                                           supportedFamilies: [.modularSmall, .circularSmall, .utilitarianSmall, .utilitarianSmallFlat, .utilitarianLarge, .graphicCorner])])
    }

    func getSupportedTimeTravelDirections(for _: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([])
    }

    private func template(for complication: CLKComplication, count: Int) -> CLKComplicationTemplate? {
        switch complication.family {
        case .modularSmall:
            return CLKComplicationTemplateModularSmallStackImage(line1ImageProvider: CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128")),
                                                                 line2TextProvider: CLKSimpleTextProvider(text: String(count)))

        case .circularSmall:
            return CLKComplicationTemplateCircularSmallStackImage(line1ImageProvider: CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128")),
                                                                  line2TextProvider: CLKSimpleTextProvider(text: String(count)))

        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: CLKSimpleTextProvider(text: String(count)),
                                                               imageProvider: CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128")))

        case .utilitarianLarge:
            let shortText = String(count)
            let text = count == 0 ? "NO ITEMS" : "\(shortText) ITEMS"
            return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider(text: text, shortText: shortText),
                                                               imageProvider: CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128")))

        case .graphicCorner:
            let shortText = String(count)
            let text = count == 0 ? "NO ITEMS" : "\(shortText) ITEMS"
            return CLKComplicationTemplateGraphicCornerTextImage(textProvider: CLKSimpleTextProvider(text: text, shortText: shortText),
                                                                 imageProvider: CLKFullColorImageProvider(fullColorImage: #imageLiteral(resourceName: "gladysCorner")))

        default:
            return nil
        }
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        let entry: CLKComplicationTimelineEntry?
        if let template = template(for: complication, count: GladysWatchModel.shared.reportedCount) {
            entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        } else {
            entry = nil
        }

        handler(entry)
    }

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(template(for: complication, count: 23))
    }

    static func reloadComplications() {
        let s = CLKComplicationServer.sharedInstance()
        s.activeComplications?.forEach {
            s.reloadTimeline(for: $0)
        }
    }
}
