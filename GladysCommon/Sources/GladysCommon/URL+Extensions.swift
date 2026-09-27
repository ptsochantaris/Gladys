import Foundation

public nonisolated extension URL {
    var urlFileContent: Data {
        Data("[InternetShortcut]\r\nURL=\(absoluteString)\r\n".utf8)
    }
}
