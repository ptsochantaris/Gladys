//
//  ImageCache.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

#if os(iOS)
import UIKit
#else
import Cocoa
#endif
import CloudKit

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

let imageCache = NSCache<NSString, IMAGE>()
let imageProcessingQueue = DispatchQueue(label: "build.bru.Gladys.imageProcessing", qos: .utility, attributes: [], autoreleaseFrequency: .workItem, target: nil)

let folderUrlCache = NSCache<NSUUID, NSURL>()
let cloudKitDataPathCache = NSCache<NSUUID, NSURL>()
let cloudKitShareDataPathCache = NSCache<NSUUID, NSURL>()
let imagePathCache = NSCache<NSUUID, NSURL>()
let bytesPathCache = NSCache<NSUUID, NSURL>()
let cloudKitRecordCache = NSCache<NSUUID, CKRecordCacheEntry>()
let cloudKitShareCache = NSCache<NSUUID, CKShareCacheEntry>()

func clearCaches() {
	for drop in Model.drops {
		for component in drop.typeItems {
			component.clearCachedFields()
		}
	}

	imageCache.removeAllObjects()
	folderUrlCache.removeAllObjects()
	cloudKitDataPathCache.removeAllObjects()
	cloudKitShareDataPathCache.removeAllObjects()
	imagePathCache.removeAllObjects()
	bytesPathCache.removeAllObjects()
	cloudKitRecordCache.removeAllObjects()
	cloudKitShareCache.removeAllObjects()
}

func clearCacheData(for uuid: UUID) {
	let nsuuid = uuid as NSUUID
	folderUrlCache.removeObject(forKey: nsuuid)
	cloudKitDataPathCache.removeObject(forKey: nsuuid)
	cloudKitShareDataPathCache.removeObject(forKey: nsuuid)
	imagePathCache.removeObject(forKey: nsuuid)
	bytesPathCache.removeObject(forKey: nsuuid)
	cloudKitRecordCache.removeObject(forKey: nsuuid)
	cloudKitShareCache.removeObject(forKey: nsuuid)
}
