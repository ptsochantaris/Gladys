import Foundation

@MainActor
public protocol HighlightListener: AnyObject, Sendable {
    func highlightItem(request: HighlightRequest) async
}

@MainActor
public struct HighlightRequest: Sendable {
    public enum Action: Sendable {
        case none, detail, open, preview(String?), userDefault
    }

    public let uuid: String
    public let extraAction: Action

    public struct Registration: Hashable, Sendable {
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public let id = UUID()
        weak var listener: HighlightListener?

        public func cancel() {
            Task { @MainActor in
                HighlightRequest.registrations.remove(self)
            }
        }
    }

    private static var registrations = Set<Registration>()

    public static func registerListener(listener: some HighlightListener) -> Registration {
        let registration = Registration(listener: listener)
        registrations.insert(registration)
        return registration
    }

    public static func send(uuid: String, extraAction: Action) {
        let request = HighlightRequest(uuid: uuid, extraAction: extraAction)
        Task {
            for registration in registrations {
                await registration.listener?.highlightItem(request: request)
            }
        }
    }
}
