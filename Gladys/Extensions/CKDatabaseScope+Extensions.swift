//
//  CKDatabase+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 12/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CloudKit

enum RecordChangeCheck {
    case none, changed, tagOnly
    
    init(localRecord: CKRecord?, remoteRecord: CKRecord) {
        if localRecord?.recordChangeTag == remoteRecord.recordChangeTag {
            self = .none
        } else {
            let localModification = localRecord?.modificationDate ?? .distantPast
            let remoteModification = remoteRecord.modificationDate ?? .distantFuture
            if localModification < remoteModification {
                self = .changed
            } else {
                self = .tagOnly
            }
        }
    }
}

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
