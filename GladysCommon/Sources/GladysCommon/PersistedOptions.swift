import Foundation

public enum DefaultTapAction: Int {
    case infoPanel = 0, preview, open, copy, none
}

public enum PersistedOptions {
    public static let defaults = UserDefaults(suiteName: groupName)!

    private static var wideModeCache: Bool?
    public static var wideMode: Bool {
        get {
            if let c = wideModeCache {
                return c
            }
            let w = _wideMode
            wideModeCache = w
            return w
        }
        set {
            wideModeCache = newValue
            _wideMode = newValue
        }
    }

    @UserDefault(key: "wideMode", defaultValue: false)
    private static var _wideMode: Bool

    @UserDefault(key: "extensionRequestedSync", defaultValue: false)
    public static var extensionRequestedSync: Bool

    @UserDefault(key: "autoGenerateLabelsFromText", defaultValue: false)
    public static var autoGenerateLabelsFromText: Bool

    @UserDefault(key: "autoGenerateLabelsFromImage", defaultValue: false)
    public static var autoGenerateLabelsFromImage: Bool

    @UserDefault(key: "transcribeSpeechFromMedia", defaultValue: false)
    public static var transcribeSpeechFromMedia: Bool

    @UserDefault(key: "includeUrlImagesInMlLogic", defaultValue: false)
    public static var includeUrlImagesInMlLogic: Bool

    @UserDefault(key: "autoGenerateTextFromImage", defaultValue: false)
    public static var autoGenerateTextFromImage: Bool

    @UserDefault(key: "setLabelsWhenActioning", defaultValue: false)
    public static var setLabelsWhenActioning: Bool

    @UserDefault(key: "fullScreenPreviews", defaultValue: false)
    public static var fullScreenPreviews: Bool

    @UserDefault(key: "showCopyMoveSwitchSelector", defaultValue: false)
    public static var showCopyMoveSwitchSelector: Bool

    @UserDefault(key: "displayNotesInMainView", defaultValue: true)
    public static var displayNotesInMainView: Bool

    @UserDefault(key: "displayLabelsInMainView", defaultValue: true)
    public static var displayLabelsInMainView: Bool

    @UserDefault(key: "removeItemsWhenDraggedOut", defaultValue: false)
    public static var removeItemsWhenDraggedOut: Bool

    @UserDefault(key: "dontAutoLabelNewItems", defaultValue: false)
    public static var dontAutoLabelNewItems: Bool

    @UserDefault(key: "exportOnlyVisibleItems", defaultValue: false)
    public static var exportOnlyVisibleItems: Bool

    @UserDefault(key: "separateItemPreference", defaultValue: false)
    public static var separateItemPreference: Bool

    @UserDefault(key: "forceTwoColumnPreference", defaultValue: false)
    public static var forceTwoColumnPreference: Bool

    @UserDefault(key: "exclusiveMultipleLabels", defaultValue: false)
    public static var exclusiveMultipleLabels: Bool

    @UserDefault(key: "autoArchiveUrlComponents", defaultValue: false)
    public static var autoArchiveUrlComponents: Bool

    @EnumUserDefault(key: "actionOnTap", defaultValue: .infoPanel)
    public static var actionOnTap: DefaultTapAction

    @EnumUserDefault(key: "actionOnTouchbar", defaultValue: .infoPanel)
    public static var actionOnTouchbar: DefaultTapAction

    @UserDefault(key: "lastSelectedPreferencesTab", defaultValue: 0)
    public static var lastSelectedPreferencesTab: Int

    @OptionalUserDefault(key: "lastPushToken", emptyValue: Data())
    public static var lastPushToken: Data?

    @UserDefault(key: "inclusiveSearchTerms", defaultValue: false)
    public static var inclusiveSearchTerms: Bool

    @OptionalUserDefault(key: "LastRanVersion", emptyValue: nil)
    public static var lastRanVersion: String?

    @UserDefault(key: "AutomaticallyConvertWebLinks", defaultValue: false)
    public static var automaticallyDetectAndConvertWebLinks: Bool

    @UserDefault(key: "ReadAndStoreFinderTagsAsLabels", defaultValue: false)
    public static var readAndStoreFinderTagsAsLabels: Bool

    @UserDefault(key: "BlockGladysUrlRequests", defaultValue: false)
    public static var blockGladysUrlRequests: Bool

    @UserDefault(key: "badgeIconWithItemCount", defaultValue: false)
    public static var badgeIconWithItemCount: Bool

    @UserDefault(key: "migratedSubscriptions8", defaultValue: false)
    public static var migratedSubscriptions8: Bool

    @UserDefault(key: "requestInlineDrops", defaultValue: false)
    public static var requestInlineDrops: Bool
}
