//
//  PersistedOptions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

enum DefaultTapAction: Int {
    case infoPanel = 0, preview, open, copy, none
}

enum PersistedOptions {
    static let defaults = UserDefaults(suiteName: groupName)!

    private static var wideModeCache: Bool?
    static var wideMode: Bool {
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
    static var extensionRequestedSync: Bool

    @UserDefault(key: "autoGenerateLabelsFromText", defaultValue: false)
    static var autoGenerateLabelsFromText: Bool

    @UserDefault(key: "autoGenerateLabelsFromImage", defaultValue: false)
    static var autoGenerateLabelsFromImage: Bool

    @UserDefault(key: "transcribeSpeechFromMedia", defaultValue: false)
    static var transcribeSpeechFromMedia: Bool

    @UserDefault(key: "includeUrlImagesInMlLogic", defaultValue: false)
    static var includeUrlImagesInMlLogic: Bool

    @UserDefault(key: "autoGenerateTextFromImage", defaultValue: false)
    static var autoGenerateTextFromImage: Bool

    @UserDefault(key: "setLabelsWhenActioning", defaultValue: false)
    static var setLabelsWhenActioning: Bool

    @UserDefault(key: "fullScreenPreviews", defaultValue: false)
    static var fullScreenPreviews: Bool

    @UserDefault(key: "showCopyMoveSwitchSelector", defaultValue: false)
    static var showCopyMoveSwitchSelector: Bool

    @UserDefault(key: "displayNotesInMainView", defaultValue: false)
    static var displayNotesInMainView: Bool

    @UserDefault(key: "displayLabelsInMainView", defaultValue: false)
    static var displayLabelsInMainView: Bool

    @UserDefault(key: "removeItemsWhenDraggedOut", defaultValue: false)
    static var removeItemsWhenDraggedOut: Bool

    @UserDefault(key: "mirrorFilesToDocuments", defaultValue: false)
    static var mirrorFilesToDocuments: Bool

    @UserDefault(key: "dontAutoLabelNewItems", defaultValue: false)
    static var dontAutoLabelNewItems: Bool

    @UserDefault(key: "exportOnlyVisibleItems", defaultValue: false)
    static var exportOnlyVisibleItems: Bool

    @UserDefault(key: "separateItemPreference", defaultValue: false)
    static var separateItemPreference: Bool

    @UserDefault(key: "forceTwoColumnPreference", defaultValue: false)
    static var forceTwoColumnPreference: Bool

    @UserDefault(key: "pasteShortcutAutoDonated", defaultValue: false)
    static var pasteShortcutAutoDonated: Bool

    @UserDefault(key: "exclusiveMultipleLabels", defaultValue: false)
    static var exclusiveMultipleLabels: Bool

    @UserDefault(key: "autoArchiveUrlComponents", defaultValue: false)
    static var autoArchiveUrlComponents: Bool

    @EnumUserDefault(key: "actionOnTap", defaultValue: .infoPanel)
    static var actionOnTap: DefaultTapAction

    @EnumUserDefault(key: "actionOnTouchbar", defaultValue: .infoPanel)
    static var actionOnTouchbar: DefaultTapAction

    @UserDefault(key: "lastSelectedPreferencesTab", defaultValue: 0)
    static var lastSelectedPreferencesTab: Int

    @OptionalUserDefault(key: "lastPushToken", emptyValue: emptyData)
    static var lastPushToken: Data?

    @UserDefault(key: "inclusiveSearchTerms", defaultValue: false)
    static var inclusiveSearchTerms: Bool

    @OptionalUserDefault(key: "LastRanVersion", emptyValue: nil)
    static var lastRanVersion: String?

    @UserDefault(key: "AutomaticallyConvertWebLinks", defaultValue: false)
    static var automaticallyDetectAndConvertWebLinks: Bool

    @UserDefault(key: "ReadAndStoreFinderTagsAsLabels", defaultValue: false)
    static var readAndStoreFinderTagsAsLabels: Bool

    @UserDefault(key: "BlockGladysUrlRequests", defaultValue: false)
    static var blockGladysUrlRequests: Bool

    @UserDefault(key: "badgeIconWithItemCount", defaultValue: false)
    static var badgeIconWithItemCount: Bool

    @UserDefault(key: "migratedSubscriptions7", defaultValue: false)
    static var migratedSubscriptions7: Bool

    @UserDefault(key: "requestInlineDrops", defaultValue: false)
    static var requestInlineDrops: Bool
}
