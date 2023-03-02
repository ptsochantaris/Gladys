import CloudKit
import ExceptionCatcher
import Foundation
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
        do {
            return try ExceptionCatcher.catch {
                try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)
            }
        } catch {
            return nil
        }
    }

    public static func unarchive(_ data: Data) -> Any? {
        do {
            return try ExceptionCatcher.catch {
                try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
            }
        } catch {
            return nil
        }
    }
}
