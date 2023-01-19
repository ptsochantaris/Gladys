import Foundation

public extension NSAttributedString {
    var toData: Data? {
        try? data(from: NSRange(location: 0, length: string.count), documentAttributes: [:])
    }
}
