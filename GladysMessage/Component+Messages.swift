import Foundation
import MobileCoreServices

extension Component {
    var attachPriority: Int {
        if fileExtension == nil {
            return 0
        }
        if typeConforms(to: .audiovisualContent) {
            return 40
        }
        if typeConforms(to: .image) {
            return 30
        }
        if typeConforms(to: .compositeContent) {
            return 20
        }
        if typeConforms(to: .contact) {
            return 15
        }
        if typeConforms(to: .content) {
            return 10
        }
        return 0
    }

    @MainActor
    var sharedLink: URL {
        let f = FileManager.default
        guard f.fileExists(atPath: bytesPath.path) else { return bytesPath }

        let sharedPath = folderUrl.appendingPathComponent("shared-blob")
        let linkURL = sharedPath.appendingPathComponent("shared").appendingPathExtension(fileExtension ?? "bin")
        let originalURL = bytesPath
        if f.fileExists(atPath: linkURL.path), Model.modificationDate(for: linkURL) == Model.modificationDate(for: originalURL) {
            return linkURL
        }

        log("Updating shared link at \(linkURL.path)")

        do {
            if f.fileExists(atPath: sharedPath.path) {
                try f.removeItem(at: sharedPath)
            }
            try f.createDirectory(atPath: sharedPath.path, withIntermediateDirectories: true, attributes: nil)
            try f.linkItem(at: originalURL, to: linkURL)
        } catch {
            log("Warning: Error while creating a shared link: \(error.finalDescription)")
        }

        return linkURL
    }
}
