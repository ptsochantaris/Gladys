//
//  Component+iOS.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/01/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension Component {
    var componentIcon: UIImage? {
        set {
            let ipath = imagePath
            if let n = newValue {
                if let data = n.pngData() {
                    try? data.write(to: ipath)
                }
            } else {
                try? FileManager.default.removeItem(at: ipath)
            }
        }
        get {
            let i = UIImage.fromFile(imagePath)
            return displayIconTemplate ? i?.withRenderingMode(.alwaysTemplate) : i
        }
    }
}
