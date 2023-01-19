import CommonCrypto
import Foundation

public func sha1(_ input: String) -> Data {
    input.utf8CString.withUnsafeBytes { bytes -> Data in
        let len = Int(CC_SHA1_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: len)
        CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count), &digest)
        return Data(bytes: digest, count: len)
    }
}
