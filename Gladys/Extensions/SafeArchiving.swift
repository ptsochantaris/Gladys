//
//  SafeArchiving.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 18/01/2023.
//  Copyright © 2023 Paul Tsochantaris. All rights reserved.
//

import Foundation
import GladysCommon
import CloudKit
import MapKit

public enum SafeArchiving {
    private static let allowedClasses = [
        NSString.classForKeyedUnarchiver(),
        NSAttributedString.classForKeyedUnarchiver(),
        COLOR.classForKeyedUnarchiver(),
        IMAGE.classForKeyedUnarchiver(),
        MKMapItem.classForKeyedUnarchiver(),
        NSURL.classForKeyedUnarchiver(),
        NSArray.classForKeyedUnarchiver(),
        NSDictionary.classForKeyedUnarchiver(),
        NSSet.classForKeyedUnarchiver(),
        CKServerChangeToken.classForKeyedUnarchiver(),
        NSDate.classForKeyedUnarchiver()
    ]
    
    public static func archive(_ object: Any) -> Data? {
        return try! NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false) // TODO
    }
    
    public static func unarchive(_ data: Data) -> Any? {
        return try! NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
    }
}
