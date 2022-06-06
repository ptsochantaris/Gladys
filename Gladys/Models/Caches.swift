//
//  ImageCache.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CloudKit
import Foundation

final class CKRecordCacheEntry {
    let record: CKRecord?
    init(record: CKRecord?) {
        self.record = record
    }
}

final class CKShareCacheEntry {
    let share: CKShare?
    init(share: CKShare?) {
        self.share = share
    }
}

let folderUrlCache = Cache<UUID, URL>()
let cloudKitDataPathCache = Cache<UUID, URL>()
let cloudKitShareDataPathCache = Cache<UUID, URL>()
let imagePathCache = Cache<UUID, URL>()
let bytesPathCache = Cache<UUID, URL>()
let cloudKitRecordCache = Cache<UUID, CKRecordCacheEntry>()
let cloudKitShareCache = Cache<UUID, CKShareCacheEntry>()

func clearCacheData(for uuid: UUID) {
    folderUrlCache[uuid] = nil
    cloudKitDataPathCache[uuid] = nil
    cloudKitShareDataPathCache[uuid] = nil
    imagePathCache[uuid] = nil
    bytesPathCache[uuid] = nil
    cloudKitRecordCache[uuid] = nil
    cloudKitShareCache[uuid] = nil
}
