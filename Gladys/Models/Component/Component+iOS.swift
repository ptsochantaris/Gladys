//
//  Component+iOS.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/01/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension Component {
    var displayIcon: UIImage? {
        set {
            let ipath = imagePath
            if let n = newValue {
                if let data = n.pngData() {
                    try? data.write(to: ipath)
                }
            } else if FileManager.default.fileExists(atPath: ipath.path) {
                try? FileManager.default.removeItem(at: ipath)
            }
        }
        get {
            if let data = Data.forceMemoryMapped(contentsOf: imagePath) {
                if displayIconTemplate {
                    let i = UIImage(data: data, scale: UIScreen.main.scale)
                    return i?.withRenderingMode(.alwaysTemplate)
                } else {
                    return UIImage(data: data)
                }
            } else {
                return nil
            }
        }
    }
}
