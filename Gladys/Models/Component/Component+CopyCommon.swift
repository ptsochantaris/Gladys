//
//  Component+CopyCommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Component {
    var dataForDropping: Data? {
        if Thread.isMainThread {
            return _dataForDropping
        } else {
            return DispatchQueue.main.sync {
                return _dataForDropping
            }
        }
    }

    private var _dataForDropping: Data? {
        if classWasWrapped, typeIdentifier.hasPrefix("public.") {
            let decoded = decode()
            if let s = decoded as? String {
                return Data(s.utf8)
            } else if let s = decoded as? NSAttributedString {
                return s.toData
            } else if let s = decoded as? URL {
                let urlString = s.absoluteString
                return try? PropertyListSerialization.data(fromPropertyList: [urlString, "", ["title": urlDropTitle]], format: .binary, options: 0)
            }
        }
        if !classWasWrapped, typeIdentifier == "public.url", let s = encodedUrl {
            let urlString = s.absoluteString
            return try? PropertyListSerialization.data(fromPropertyList: [urlString, "", ["title": urlDropTitle]], format: .binary, options: 0)
        }
        return nil
    }

    private var urlDropTitle: String {
        parent?.trimmedSuggestedName ?? oneTitle
    }
}
