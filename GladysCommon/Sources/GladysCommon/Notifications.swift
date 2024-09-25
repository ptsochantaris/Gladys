import Foundation

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
    public let providers: [DataImporter]
    public let overrides: ImportOverrides?
}

extension Notification: @unchecked @retroactive Sendable {}

public extension Notification.Name {
    static let ItemCollectionNeedsDisplay = Notification.Name("ItemCollectionNeedsDisplay")
    static let ModelDataUpdated = Notification.Name("ModelDataUpdated")
    static let ItemsAddedBySync = Notification.Name("ItemsAddedBySync")
    static let ItemsRemoved = Notification.Name("ItemsRemoved")
    static let LabelsUpdated = Notification.Name("LabelsUpdated")
    static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
    static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
    static let ReachabilityChanged = Notification.Name("ReachabilityChanged")
    static let IngestComplete = Notification.Name("IngestComplete")
    static let AcceptStarting = Notification.Name("AcceptStarting")
    static let AcceptEnding = Notification.Name("AcceptEnding")
    static let ForegroundDisplayedItem = Notification.Name("ForegroundDisplayedItem")
    static let AlwaysOnTopChanged = Notification.Name("AlwaysOnTopChanged")
    static let ClipboardSnoopingChanged = Notification.Name("ClipboardSnoopingChanged")
}

public func sendNotification(name: Notification.Name, object: Sendable? = nil) {
    Task { @MainActor in
        await Task.yield()
        NotificationCenter.default.post(name: name, object: object)
    }
}

public func notifications(for name: Notification.Name, block: @MainActor @escaping (Any?) async -> Void) {
    Task {
        for await notification in NotificationCenter.default.notifications(named: name) {
            let obj = notification.object
            await block(obj)
        }
    }
}

#if canImport(UIKit) && !canImport(WatchKit)
    import UIKit

    public struct UIRequest: Sendable {
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
