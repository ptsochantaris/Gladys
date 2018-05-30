//
//  ArchivedDropItemType+CopyCommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension ArchivedDropItemType {
	var dataForWrappedItem: Data? {
		if classWasWrapped && typeIdentifier.hasPrefix("public.") {
			let decoded = decode()
			if let s = decoded as? String {
				return s.data(using: .utf8)
			} else if let s = decoded as? NSAttributedString {
				return s.toData
			} else if let s = decoded as? NSURL {
				return s.absoluteString?.data(using: .utf8)
			}
		}
		return nil
	}
}
