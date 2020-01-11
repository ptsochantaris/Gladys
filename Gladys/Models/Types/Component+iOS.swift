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
                if let data = try? Data(contentsOf: imagePath) {
                    let i = UIImage(data: data, scale: displayIconScale)
                    if displayIconTemplate {
                        return i?.withRenderingMode(.alwaysTemplate)
                    } else {
                        return i
                    }
                } else {
                    return nil
                }
            }
        }
    }
}
