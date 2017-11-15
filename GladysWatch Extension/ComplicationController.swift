//
//  ComplicationController.swift
//  GladysWatch Extension
//
//  Created by Paul Tsochantaris on 14/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import ClockKit


class ComplicationController: NSObject, CLKComplicationDataSource {
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
		switch complication.family {

		case .modularSmall, .extraLarge, .utilitarianSmallFlat, .utilitarianSmall, .circularSmall, .modularLarge:
			handler(nil)

		case .utilitarianLarge:
			let text = PersistedOptions.watchComplicationText.isEmpty ? "Set text from items" : PersistedOptions.watchComplicationText

			let t = CLKComplicationTemplateUtilitarianLargeFlat()
			t.textProvider = CLKSimpleTextProvider(text: text)

			let e = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: t)
			handler(e)
		}
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        handler(nil)
    }

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
			switch complication.family {
			case .modularSmall, .extraLarge, .utilitarianSmallFlat, .utilitarianSmall, .circularSmall, .modularLarge:
				handler(nil)
			case .utilitarianLarge:
				let t = CLKComplicationTemplateUtilitarianLargeFlat()
				t.textProvider = CLKSimpleTextProvider(text: "Set text from items")
				handler(t)
			}
	}
}
