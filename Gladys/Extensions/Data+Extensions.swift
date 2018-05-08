//
//  Data+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Data {
	var isPlist: Bool {
		guard count > 6 else { return false }
		return withUnsafeBytes { (x: UnsafePointer<UInt8>) -> Bool in
			return x[0] == 0x62
				&& x[1] == 0x70
				&& x[2] == 0x6c
				&& x[3] == 0x69
				&& x[4] == 0x73
				&& x[5] == 0x74
		}
	}
	var isZip: Bool {
		guard count > 3 else { return false }
		return withUnsafeBytes { (x: UnsafePointer<UInt8>) -> Bool in
			return x[0] == 0x50
				&& x[1] == 0x4B
				&& ((x[2] == 3 && x[3] == 4) || (x[2] == 5 && x[3] == 6) || (x[2] == 7 && x[3] == 8))
		}
	}
}
