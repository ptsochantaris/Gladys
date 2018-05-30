//
//  NSAttributedString+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 30/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension NSAttributedString {
	var toData: Data? {
		return try? data(from: NSMakeRange(0, string.count), documentAttributes: [:])
	}
}
