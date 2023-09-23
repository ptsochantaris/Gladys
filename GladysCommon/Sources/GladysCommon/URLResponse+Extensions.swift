import Foundation

extension URLResponse {
    var guessedEncoding: String.Encoding {
        if let encodingName = textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding == kCFStringEncodingInvalidId {
                return .utf8
            } else {
                let swiftEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                return String.Encoding(rawValue: swiftEncoding)
            }
        } else {
            log("Warning: Fallback encoding for site text")
            return .utf8
        }
    }
}
