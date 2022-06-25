import Foundation

extension Component {
    @MainActor
    var dataForDropping: Data? {
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

    @MainActor
    private var urlDropTitle: String {
        parent?.trimmedSuggestedName ?? oneTitle
    }
}
