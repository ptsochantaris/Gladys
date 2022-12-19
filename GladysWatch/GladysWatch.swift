import GladysFramework
import WatchConnectivity
import SwiftUI

private let formatter: DateFormatter = {
    let d = DateFormatter()
    d.dateStyle = .medium
    d.timeStyle = .medium
    d.doesRelativeDateFormatting = true
    return d
}()

private final class ImageCache {
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
        guard case .none = imageState else {
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
        WCSession.default.sendMessage(["image": id, "width": size.width, "height": size.height], replyHandler: { reply in
            if let r = reply["image"] as? Data {
                if let i = UIImage(data: r) {
                    ImageCache.setImageData(r, for: cacheKey)
                    Task { @MainActor in
                        self.imageState = .loaded(image: i)
                    }
                }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                self.imageState = .empty
            }
        })
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

final class GladysWatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var reportedCount = 0
    @Published var dropList = [Drop]()

    static let shared = GladysWatchModel()

    enum State {
        case loading, empty, list
    }
    
    var state = State.loading

    private func extractDropList(from context: [String: Any]) -> ([[String: Any]], Int) {
        if
            let reportedCount = context["total"] as? Int,
            let compressedData = context["dropList"] as? Data,
            let uncompressedData = compressedData.data(operation: .decompress),
            let itemInfo = SafeArchiving.unarchive(uncompressedData) as? [[String: Any]] {
            var count = 1
            let list = itemInfo.map { dict -> [String: Any] in
                var d = dict
                d["it"] = "\(count) of \(reportedCount)"
                count += 1
                return d
            }
            return (list, reportedCount)
        } else {
            return ([], 0)
        }
    }

    private func receivedInfo(_ info: [String: Any]) {
        let (dropList, reportedCount) = extractDropList(from: info)
        DispatchQueue.main.sync {
            self.reportedCount = reportedCount
            self.dropList = dropList.compactMap { Drop(json: $0) }
            ComplicationDataSource.reloadComplications()
            ImageCache.trimUnaccessedEntries()
            if dropList.isEmpty {
                state = .empty
            } else {
                state = .list
            }
        }
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receivedInfo(userInfo)
    }

    func getFullUpdate(session: WCSession) {
        if session.activationState == .activated {
            session.sendMessage(["update": "full"], replyHandler: { [weak self] info in
                self?.receivedInfo(info)
            }, errorHandler: nil)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        getFullUpdate(session: session)
    }

    func session(_: WCSession, didReceiveApplicationContext _: [String: Any]) {}
}

private struct Label: View {
    var text: String
    var lineLimit = 0
    
    var body: some View {
        Text(text)
            .multilineTextAlignment(.center)
            .font(.caption2)
            .lineLimit(lineLimit)
            .shadow(color: .black, radius: 2)
            .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
            .background {
                Color(white: 0, opacity: 0.5)
                    .cornerRadius(12)
            }
            .scenePadding()
    }
}

private struct DropView: View {
    @ObservedObject var drop: Drop
    
    var body: some View {
        ZStack(alignment: .center) {
            Color(.darkGray)
                .ignoresSafeArea()

            switch drop.imageState {
            case .empty:
                Spacer()
            case .loading, .none:
                ProgressView()
            case .loaded(let image):
                GeometryReader { reader in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: reader.size.width, height: reader.size.height)
                }
                .ignoresSafeArea()
            }

            switch drop.uiState {
            case .noText:
                Spacer()

            case .text:
                VStack {
                    Label(text: drop.title, lineLimit: 3)
                    Spacer()
                    Label(text: formatter.string(from: drop.imageDate), lineLimit: 1)
                }
            case .action(let label):
                Color(white: 0, opacity: 0.8)
                    .ignoresSafeArea()
                Text(label)
                
            case .menu(let previousState):
                Color(white: 0, opacity: 0.8)
                    .ignoresSafeArea()
                ScrollView {
                    VStack {
                        Button {
                            drop.viewOnDeviceSelected()
                        } label: {
                            Text("Open on Phone")
                        }
                        Button {
                            drop.copySelected()
                        } label: {
                            Text("Copy")
                        }
                        Button {
                            drop.moveToTopSelected()
                        } label: {
                            Text("Move to Top")
                        }
                        Button(role: .destructive) {
                            drop.deleteSelected()
                        } label: {
                            Text("Delete")
                        }
                        Button(role: .cancel) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                drop.uiState = previousState
                            }
                        } label: {
                            Text("Cancel")
                        }
                    }
                }
            }
        }
        .onTapGesture {
            switch drop.uiState {
            case .text:
                withAnimation(.easeInOut(duration: 0.2)) {
                    drop.uiState = .noText
                }
            case .noText:
                withAnimation(.easeInOut(duration: 0.2)) {
                    drop.uiState = .text
                }
            case .action, .menu:
                break
            }
        }
        .onLongPressGesture {
            switch drop.uiState {
            case .text, .noText:
                withAnimation(.easeInOut(duration: 0.2)) {
                    drop.uiState = .menu(over: drop.uiState)
                }
            case .menu, .action:
                break
            }
        }
        .onAppear {
            drop.fetchImage()
        }
    }
}

@main
struct GladysWatch: App {
    @ObservedObject var model = GladysWatchModel.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let session = WCSession.default
        session.delegate = model
        session.activate()
        model.getFullUpdate(session: session)
    }

    var body: some Scene {
        WindowGroup {
            switch model.state {
            case .loading:
                Text("Loading…")
            case .empty:
                Text("Items in your collection will appear here")
            case .list:
                TabView {
                    ForEach(model.dropList) { item in
                        DropView(drop: item)
                    }
                }
                .tabViewStyle(.carousel)
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                model.getFullUpdate(session: WCSession.default)

            case .background, .inactive:
                break

            @unknown default:
                break
            }
        }
    }
}
