import Foundation

public extension URL {
    var urlFileContent: Data {
        Data("[InternetShortcut]\r\nURL=\(absoluteString)\r\n".utf8)
    }
}
