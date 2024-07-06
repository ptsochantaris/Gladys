import SwiftUI
import WatchConnectivity

private let formatter: DateFormatter = {
    let d = DateFormatter()
    d.dateStyle = .medium
    d.timeStyle = .medium
    d.doesRelativeDateFormatting = true
    return d
}()

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
    @StateObject var drop: Drop

    var body: some View {
        ZStack(alignment: .center) {
            Color(.darkGray)
                .ignoresSafeArea()

            switch drop.imageState {
            case .empty:
                Spacer()
            case .loading, .none:
                ProgressView()
            case let .loaded(image):
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

            case let .action(label):
                Color(white: 0, opacity: 0.8)
                    .ignoresSafeArea()
                Text(label)

            case let .menu(previousState):
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
        .onAppear {
            drop.fetchImage()
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
            case .noText, .text:
                withAnimation(.easeInOut(duration: 0.2)) {
                    drop.uiState = .menu(over: drop.uiState)
                }
            case .action, .menu:
                break
            }
        }
    }
}

@main
struct GladysWatch: App {
    @StateObject var model = GladysWatchModel.shared
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
        .onChange(of: scenePhase) {
            switch scenePhase {
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
