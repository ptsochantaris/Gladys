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
        get {
            UIImage.fromFile(imagePath, template: displayIconTemplate)
        }
        set {
            let ipath = imagePath
            if let n = newValue, let data = n.pngData() {
                try? data.write(to: ipath)
            } else {
                try? FileManager.default.removeItem(at: ipath)
            }
        }
    }
}
