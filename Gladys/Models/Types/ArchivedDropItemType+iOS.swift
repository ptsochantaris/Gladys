//
//  ArchivedDropItemType+iOS.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/01/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension ArchivedDropItemType {
    var displayIcon: UIImage? {
        set {
            let ipath = imagePath
            dataAccessQueue.async {
                if let n = newValue {
                    if let data = n.pngData() {
                        try? data.write(to: ipath)
                    }
                } else if FileManager.default.fileExists(atPath: ipath.path) {
                    try? FileManager.default.removeItem(at: ipath)
                }
            }
        }
        get {
            return dataAccessQueue.sync {
                var i: UIImage?
                if let data = (try? Data(contentsOf: imagePath)) {
                    i = UIImage(data: data, scale: displayIconScale)
                }
                if displayIconTemplate {
                    i = i?.withRenderingMode(.alwaysTemplate)
                }
                return i
            }
        }
    }
}
