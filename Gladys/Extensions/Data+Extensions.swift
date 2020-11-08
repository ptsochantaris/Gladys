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
		return withUnsafeBytes { ptr -> Bool in
			guard let x = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
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
		return withUnsafeBytes { ptr -> Bool in
			guard let x = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
			return x[0] == 0x50
				&& x[1] == 0x4B
				&& ((x[2] == 3 && x[3] == 4) || (x[2] == 5 && x[3] == 6) || (x[2] == 7 && x[3] == 8))
		}
	}
    static func forceMemoryMapped(contentsOf url: URL) -> Data? {
        guard let cPath = url.absoluteURL.path.cString(using: .utf8) else {
            log("Warning, could not resolve \(url.absoluteURL.path)")
            return nil
        }
        
        var st = stat()
        if stat(cPath, &st) != 0 {
            log("Warning, could not size \(url.absoluteURL.path)")
            return nil
        }
        let count = Int(st.st_size)

        let fd = open(cPath, O_RDONLY)
        if fd < 0 {
            log("Warning, could not open \(url.absoluteURL.path)")
            return nil
        }
        
        defer {
            if close(fd) != 0 {
                log("Warning, error when closing \(url.absoluteURL.path)")
            }
        }
        
        guard let mappedBuffer = mmap(nil, count, PROT_READ, MAP_PRIVATE|MAP_FILE, fd, 0) else {
            log("Warning, could not memory map \(url.absoluteURL.path)")
            return nil
        }
                
        return Data(bytesNoCopy: mappedBuffer, count: count, deallocator: .unmap)
    }
}
