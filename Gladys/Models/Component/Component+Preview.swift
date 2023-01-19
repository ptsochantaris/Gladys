import Foundation
import GladysCommon
#if os(macOS)
    import Quartz
#else
    import QuickLook
#endif

extension Component {
    var previewTempPath: URL {
        let path = Model.temporaryDirectoryUrl.appendingPathComponent(uuid.uuidString, isDirectory: false)
        if isWebURL {
            return path.appendingPathExtension("webloc")
        } else if let f = fileExtension {
            return path.appendingPathExtension(f)
        } else {
            return path
        }
    }

    final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        let needsCleanup: Bool
        let parentUuid: UUID
        let uuid: UUID

        @MainActor
        init(typeItem: Component) {
            parentUuid = typeItem.parentUuid
            uuid = typeItem.uuid

            let blobPath = typeItem.bytesPath
            let tempPath = typeItem.previewTempPath

            needsCleanup = blobPath != tempPath

            if needsCleanup {
                let currentCount = PreviewItem.previewUrls[tempPath] ?? 0
                PreviewItem.previewUrls[tempPath] = currentCount + 1

                if currentCount == 0 {
                    let fm = FileManager.default
                    if !fm.fileExists(atPath: tempPath.path) {
                        if tempPath.pathExtension == "webloc", let url = typeItem.encodedUrl { // only happens on macOS, iOS uses another view for previewing
                            try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .binary, options: 0).write(to: tempPath)
                            log("Created temporary webloc for preview: \(tempPath.path)")
                        } else if let data = typeItem.dataForDropping {
                            try? data.write(to: tempPath)
                            log("Created temporary file for preview: \(tempPath.path)")
                        } else {
                            try? fm.linkItem(at: blobPath, to: tempPath)
                            log("Linked temporary file for preview: \(tempPath.path)")
                        }
                    }
                }
                previewItemURL = tempPath
            } else {
                previewItemURL = blobPath
            }

            previewItemTitle = typeItem.oneTitle
        }

        deinit {
            if needsCleanup, let previewItemURL {
                PreviewItem.cleanupUrl(previewItemURL: previewItemURL)
            }
        }

        static var previewUrls = [URL: Int]()
        fileprivate static func cleanupUrl(previewItemURL: URL) {
            let currentCount = previewUrls[previewItemURL] ?? 0
            if currentCount == 1 {
                previewUrls[previewItemURL] = nil
                let fm = FileManager.default
                if fm.fileExists(atPath: previewItemURL.path) {
                    try? fm.removeItem(at: previewItemURL)
                    log("Removed temporary preview at \(previewItemURL.path)")
                }
            } else {
                previewUrls[previewItemURL] = currentCount - 1
            }
        }
    }
}
