import Contacts
import GladysCommon
import MobileCoreServices
import UIKit

extension Component {
    func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool) async throws {
        if storeBytes {
            setBytes(data)
        }
        representedClass = .url
        setTitle(from: url)

        if url.isFileURL {
            log("      received local file url: \(url.path)")
            await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
        } else {
            try await handleRemoteUrl(url, data, storeBytes)
        }
    }
}
