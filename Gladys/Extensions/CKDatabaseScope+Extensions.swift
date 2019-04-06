//
//  CKDatabase+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 12/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CloudKit

extension CKDatabase.Scope {
	var keyName: String {
		switch self {
		case .public: return "1"
		case .private: return "2"
		case .shared: return "3"
		@unknown default: return "4"
		}
	}

	var logName: String {
		switch self {
		case .private: return "private"
		case .public: return "public"
		case .shared: return "shared"
		@unknown default: return "unknown"
		}
	}
}
