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

let imageCache = NSCache<NSString, IMAGE>()
let imageProcessingQueue = DispatchQueue(label: "build.bru.Gladys.imageProcessing", qos: .utility, attributes: [], autoreleaseFrequency: .workItem, target: nil)

func clearCaches() {
	ArchivedDropItem.clearCaches()
	imageCache.removeAllObjects()
}
