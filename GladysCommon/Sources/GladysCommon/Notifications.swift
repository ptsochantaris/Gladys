import Foundation

public struct HighlightRequest {
    public enum Action {
        case none, detail, open, preview(String?)
    }

    public let uuid: String
    public let extraAction: Action

    public init(uuid: String, extraAction: Action) {
        self.uuid = uuid
        self.extraAction = extraAction
    }
}

public struct ImportOverrides {
    public let title: String?
    public let note: String?
    public let labels: [String]?

    public init(title: String?, note: String?, labels: [String]?) {
        self.title = title
        self.note = note
        self.labels = labels
    }
}

public struct PasteRequest {
    public let providers: [NSItemProvider]
    public let overrides: ImportOverrides?
    public let skipVisibleErrors: Bool
}

public extension Notification.Name {
    static let ItemCollectionNeedsDisplay = Notification.Name("ItemCollectionNeedsDisplay")
    static let ModelDataUpdated = Notification.Name("ModelDataUpdated")
    static let ItemsAddedBySync = Notification.Name("ItemsAddedBySync")
    static let ItemModified = Notification.Name("ItemModified")
    static let ItemsRemoved = Notification.Name("ItemsRemoved")
    static let LabelsUpdated = Notification.Name("LabelsUpdated")
    static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
    static let DetailViewClosing = Notification.Name("DetailViewClosing")
    static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
    static let ReachabilityChanged = Notification.Name("ReachabilityChanged")
    static let IngestStart = Notification.Name("IngestStart")
    static let IngestComplete = Notification.Name("IngestComplete")
    static let AcceptStarting = Notification.Name("AcceptStarting")
    static let AcceptEnding = Notification.Name("AcceptEnding")
    static let ForegroundDisplayedItem = Notification.Name("ForegroundDisplayedItem")
    static let AlwaysOnTopChanged = Notification.Name("AlwaysOnTopChanged")
    static let ClipboardSnoopingChanged = Notification.Name("ClipboardSnoopingChanged")
    static let HighlightItemRequested = Notification.Name("HighlightItemRequested")
}

@MainActor
public func sendNotification(name: Notification.Name, object: Any?) {
    NotificationCenter.default.post(name: name, object: object)
}

#if os(macOS)
#elseif os(iOS)
    import UIKit

    public struct UIRequest {
        public let vc: UIViewController
        public let sourceView: UIView?
        public let sourceRect: CGRect?
        public let sourceButton: UIBarButtonItem?
        public let pushInsteadOfPresent: Bool
        public let sourceScene: UIWindowScene?

        public init(vc: UIViewController, sourceView: UIView?, sourceRect: CGRect?, sourceButton: UIBarButtonItem?, pushInsteadOfPresent: Bool, sourceScene: UIWindowScene?) {
            self.vc = vc
            self.sourceView = sourceView
            self.sourceRect = sourceRect
            self.sourceButton = sourceButton
            self.pushInsteadOfPresent = pushInsteadOfPresent
            self.sourceScene = sourceScene
        }
    }

    public extension Notification.Name {
        static let UIRequest = Notification.Name("UIRequest")
        static let DismissPopoversRequest = Notification.Name("DismissPopoversRequest")
        static let ResetSearchRequest = Notification.Name("ResetSearchRequest")
        static let MultipleWindowModeChange = Notification.Name("MainWindowCloseStateChange")
        static let PreferencesOpen = Notification.Name("PreferencesOpen")
        static let SectionHeaderTapped = Notification.Name("SectionHeaderTapped")
        static let SectionShowAllTapped = Notification.Name("SectionShowAllTapped")
    }
#endif
