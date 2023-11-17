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

final class Drop: Identifiable, ObservableObject {
    let id: String
    let title: String
    let imageDate: Date

    enum ImageState {
        case none, loading, empty, loaded(image: UIImage)
    }

    indirect enum UIState {
        case noText, text, menu(over: UIState), action(label: String)
    }

    @Published var imageState = ImageState.none
    @Published var uiState = UIState.text

    init?(json: [String: Any]) {
        guard let id = json["u"] as? String,
              let title = json["t"] as? String,
              let imageDate = json["d"] as? Date
        else {
            return nil
        }
        self.id = id
        self.title = title
        self.imageDate = imageDate
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
        WCSession.default.sendMessage(["image": id, "width": size.width, "height": size.height]) { reply in
            guard let r = reply["image"] as? Data, let i = UIImage(data: r) else {
                Task { @MainActor in
                    self.imageState = .empty
                }
                return
            }
            ImageCache.setImageData(r, for: cacheKey)
            Task { @MainActor in
                self.imageState = .loaded(image: i)
            }

        } errorHandler: { _ in
            Task { @MainActor in
                self.imageState = .empty
            }
        }
    }

    func viewOnDeviceSelected() {
        uiState = .action(label: "Opening item on the phone app")
        WCSession.default.sendMessage(["view": id]) { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        } errorHandler: { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        }
    }

    func copySelected() {
        uiState = .action(label: "Copying")
        WCSession.default.sendMessage(["copy": id]) { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        } errorHandler: { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        }
    }

    func moveToTopSelected() {
        uiState = .action(label: "Moving to the top of the list")
        WCSession.default.sendMessage(["moveToTop": id]) { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        } errorHandler: { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        }
    }

    func deleteSelected() {
        uiState = .action(label: "Deleting")
        WCSession.default.sendMessage(["delete": id]) { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        } errorHandler: { _ in
            Task { @MainActor in
                self.uiState = .text
            }
        }
    }
}
