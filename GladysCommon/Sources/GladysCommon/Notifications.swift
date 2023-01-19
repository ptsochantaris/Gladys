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

extension Notification.Name {
    public static let ItemCollectionNeedsDisplay = Notification.Name("ItemCollectionNeedsDisplay")
    public static let ModelDataUpdated = Notification.Name("ModelDataUpdated")
    public static let ItemsAddedBySync = Notification.Name("ItemsAddedBySync")
    public static let ItemModified = Notification.Name("ItemModified")
    public static let ItemsRemoved = Notification.Name("ItemsRemoved")
    public static let LabelsUpdated = Notification.Name("LabelsUpdated")
    public static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
    public static let DetailViewClosing = Notification.Name("DetailViewClosing")
    public static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
    public static let ReachabilityChanged = Notification.Name("ReachabilityChanged")
    public static let IngestStart = Notification.Name("IngestStart")
    public static let IngestComplete = Notification.Name("IngestComplete")
    public static let AcceptStarting = Notification.Name("AcceptStarting")
    public static let AcceptEnding = Notification.Name("AcceptEnding")
    public static let ForegroundDisplayedItem = Notification.Name("ForegroundDisplayedItem")
    public static let AlwaysOnTopChanged = Notification.Name("AlwaysOnTopChanged")
    public static let ClipboardSnoopingChanged = Notification.Name("ClipboardSnoopingChanged")
    public static let HighlightItemRequested = Notification.Name("HighlightItemRequested")
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

extension Notification.Name {
    public static let UIRequest = Notification.Name("UIRequest")
    public static let DismissPopoversRequest = Notification.Name("DismissPopoversRequest")
    public static let ResetSearchRequest = Notification.Name("ResetSearchRequest")
    public static let MultipleWindowModeChange = Notification.Name("MainWindowCloseStateChange")
    public static let PreferencesOpen = Notification.Name("PreferencesOpen")
    public static let SectionHeaderTapped = Notification.Name("SectionHeaderTapped")
    public static let SectionShowAllTapped = Notification.Name("SectionShowAllTapped")
}
#endif
