//
//  ComplicationDataSource.swift
//  GladysWatch Extension
//
//  Created by Paul Tsochantaris on 09/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import WatchKit

final class ComplicationDataSource: NSObject, CLKComplicationDataSource {

	func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
		handler([])
	}

	private func template(for complication: CLKComplication, count: Int) -> CLKComplicationTemplate? {
		switch complication.family {
		case .modularSmall:
			let t = CLKComplicationTemplateModularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128"))
			let count = String(count)
			t.line2TextProvider = CLKSimpleTextProvider(text: count)
			return t

		case .circularSmall:
			let t = CLKComplicationTemplateCircularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128"))
			let count = String(count)
			t.line2TextProvider = CLKSimpleTextProvider(text: count)
			return t

		case .utilitarianSmall, .utilitarianSmallFlat:
			let t = CLKComplicationTemplateUtilitarianSmallFlat()
			t.imageProvider = CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128"))
			let count = String(count)
			t.textProvider = CLKSimpleTextProvider(text: count)
			return t

		case .utilitarianLarge:
			let t = CLKComplicationTemplateUtilitarianLargeFlat()
			t.imageProvider = CLKImageProvider(onePieceImage: #imageLiteral(resourceName: "gladysWatch128"))
			let shortText = String(count)
			let text = count == 0 ? "NO ITEMS" : "\(shortText) ITEMS"
			t.textProvider = CLKSimpleTextProvider(text: text, shortText: shortText)
			return t

		case .graphicCorner:
			if #available(watchOSApplicationExtension 5.0, *) {
				if watchModel >= 4 {
					let t = CLKComplicationTemplateGraphicCornerTextImage()
					t.imageProvider = CLKFullColorImageProvider(fullColorImage: #imageLiteral(resourceName: "gladysCorner"))
					let shortText = String(count)
					let text = count == 0 ? "NO ITEMS" : "\(shortText) ITEMS"
					t.textProvider = CLKSimpleTextProvider(text: text, shortText: shortText)
					return t
				} else {
					return nil
				}
			} else {
				return nil
			}

		default:
			return nil
		}
	}

	private var watchModel: Int {
		#if targetEnvironment(simulator)
			return 10
		#else
		var size: size_t = 0
		sysctlbyname("hw.machine", nil, &size, nil, 0)
		var machine = CChar()
		sysctlbyname("hw.machine", &machine, &size, nil, 0)
		if let s = String(cString: &machine, encoding: String.Encoding.utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("Watch"), s.count > 5 {
			let sub = s[s.index(s.startIndex, offsetBy: 5)]
			return Int(String(sub)) ?? 0
		} else {
			return 0
		}
		#endif
	}

	func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {

		let entry: CLKComplicationTimelineEntry?
		if let template = template(for: complication, count: ExtensionDelegate.reportedCount) {
			entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
		} else {
			entry = nil
		}

		handler(entry)
	}

	func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
		handler(template(for: complication, count: 23))
	}
}
