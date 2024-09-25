import UIKit
import WatchConnectivity
import WatchKit

enum ImageCache {
    private static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

    private static let accessKeys = Set([URLResourceKey.contentAccessDateKey])

    static func setImageData(_ data: Data, for key: String) {
        let imageUrl = cacheDir.appendingPathComponent(key)
        do {
            try data.write(to: imageUrl)
        } catch {
            print("Error writing data to: \(error.localizedDescription)")
        }
    }

    static func imageData(for key: String) -> Data? {
        var imageUrl = cacheDir.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: imageUrl.path) {
            var v = URLResourceValues()
            let now = Date()
            v.contentModificationDate = now
            v.contentAccessDate = now
            try? imageUrl.setResourceValues(v)
            return try? Data(contentsOf: imageUrl, options: .mappedIfSafe)
        }
        return nil
    }

    static func trimUnaccessedEntries() {
        if let cachedFiles = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) {
            let now = Date()
            let fm = FileManager.default
            for file in cachedFiles {
                if let accessDate = (try? file.resourceValues(forKeys: accessKeys))?.contentAccessDate {
                    if now.timeIntervalSince(accessDate) > (3600 * 24 * 7) {
                        try? fm.removeItem(at: file)
                    }
                }
            }
        }
    }
}

@MainActor
@Observable
final class Drop: Identifiable {
    let id: String
    let title: String
    let imageDate: Date

    enum ImageState: Sendable {
        case none, loading, empty, loaded(image: UIImage)
    }

    indirect enum UIState {
        case noText, text, menu(over: UIState), action(label: String)
    }

    private(set) var imageState = ImageState.none
    var uiState = UIState.text

    nonisolated init(dropInfo: WatchMessage.DropInfo) {
        id = dropInfo.id
        title = dropInfo.title
        imageDate = dropInfo.imageDate
    }

    func fetchImage() {
        if case .loading = imageState {
            return
        }

        let cacheKey = id + String(imageDate.timeIntervalSinceReferenceDate) + ".dat"
        if let data = ImageCache.imageData(for: cacheKey), let i = UIImage(data: data) {
            imageState = .loaded(image: i)
            return
        }

        imageState = .loading

        let screen = WKInterfaceDevice.current()
        let size = CGSize(width: screen.screenBounds.width, height: screen.screenBounds.height)
        let request = WatchMessage.imageRequest(WatchMessage.ImageInfo(id: id, width: size.width, height: size.height))

        Task.detached { [weak self] in
            guard let self else { return }
            switch try? await WCSession.default.sendWatchMessage(request) {
            case let .imageData(data):
                if let i = UIImage(data: data) {
                    ImageCache.setImageData(data, for: cacheKey)
                    await setImageState(.loaded(image: i))
                } else {
                    await setImageState(.empty)
                }

            default:
                await setImageState(.empty)
            }
        }
    }

    func setImageState(_ newState: ImageState) {
        imageState = newState
    }

    func viewOnDeviceSelected() {
        uiState = .action(label: "Opening item on the phone app")
        Task {
            _ = try? await WCSession.default.sendWatchMessage(.view(id))
            self.uiState = .text
        }
    }

    func copySelected() {
        uiState = .action(label: "Copying")
        Task {
            _ = try? await WCSession.default.sendWatchMessage(.copy(id))
            self.uiState = .text
        }
    }

    func moveToTopSelected() {
        uiState = .action(label: "Moving to the top of the list")
        Task {
            _ = try? await WCSession.default.sendWatchMessage(.moveToTop(id))
            self.uiState = .text
        }
    }

    func deleteSelected() {
        uiState = .action(label: "Deleting")
        Task {
            _ = try? await WCSession.default.sendWatchMessage(.delete(id))
            self.uiState = .text
        }
    }
}
