//
//  ShareCommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 30/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

let sharingPasteboard = NSPasteboard.Name("build.bru.MacGladys.SharePasteboard")

extension Notification.Name {
    static let SharingPasteboardPasted = Notification.Name("SharingPasteboardPasted")
}
