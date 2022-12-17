import Foundation
import MobileCoreServices

extension ArchivedItem {
    var attachmentForMessage: URL? {
        components.first { $0.typeConforms(to: .content) }?.bytesPath
    }

    var textForMessage: (String, URL?) {
        var webURL: URL?
        for t in components {
            if let u = t.encodedUrl, !u.isFileURL {
                webURL = u as URL
                break
            }
        }
        let tile = displayTitleOrUuid
        if let webURL {
            let a = webURL.absoluteString
            if tile != a {
                return (tile, webURL)
            }
        }
        return (tile, nil)
    }

    var attachableTypeItem: Component? {
        if let i = components.max(by: { $0.attachPriority < $1.attachPriority }), i.attachPriority > 0 {
            return i
        } else {
            return nil
        }
    }
}
