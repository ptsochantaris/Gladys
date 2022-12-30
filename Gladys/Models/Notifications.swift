import Foundation

struct HighlightRequest {
    enum Action {
        case none, detail, open, preview(String?)
    }

    let uuid: String
    let extraAction: Action

    @MainActor
    var itemExists: Bool {
        Model.item(uuid: uuid) != nil
    }
}

struct PasteRequest {
    let providers: [NSItemProvider]
    let overrides: ImportOverrides?
    let skipVisibleErrors: Bool
}

extension Notification.Name {
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
func sendNotification(name: Notification.Name, object: Any?) {
    NotificationCenter.default.post(name: name, object: object)
}

#if MAINAPP
    import UIKit

    struct UIRequest {
        let vc: UIViewController
        let sourceView: UIView?
        let sourceRect: CGRect?
        let sourceButton: UIBarButtonItem?
        let pushInsteadOfPresent: Bool
        let sourceScene: UIWindowScene?
    }

    extension Notification.Name {
        static let UIRequest = Notification.Name("UIRequest")
        static let DismissPopoversRequest = Notification.Name("DismissPopoversRequest")
        static let ResetSearchRequest = Notification.Name("ResetSearchRequest")
        static let MultipleWindowModeChange = Notification.Name("MainWindowCloseStateChange")
        static let PreferencesOpen = Notification.Name("PreferencesOpen")
        static let SectionHeaderTapped = Notification.Name("SectionHeaderTapped")
        static let SectionShowAllTapped = Notification.Name("SectionShowAllTapped")
    }
#endif
