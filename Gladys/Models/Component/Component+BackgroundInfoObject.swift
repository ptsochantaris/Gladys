//
//  Component+BackgroundInfoObject.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 18/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

#if os(iOS)
import UIKit
#else
import Cocoa
#endif
import MapKit

extension Component {
	var backgroundInfoObject: (Any?, Int) {
		switch representedClass {
		case .mapItem: return (decode() as? MKMapItem, 30)
		case .color: return (decode() as? COLOR, 30)
		default: return (nil, 0)
		}
	}
}
