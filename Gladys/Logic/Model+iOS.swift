//
//  File.swift
//  
//
//  Created by Paul Tsochantaris on 05/02/2023.
//

import Foundation
import GladysCommon
import GladysUI
import UIKit
import WatchConnectivity
import Intents

extension UISceneSession {
    var associatedFilter: Filter {
        if let existing = userInfo?[kGladysMainFilter] as? Filter {
            return existing
        }
        let newFilter = Filter()
        if userInfo == nil {
            userInfo = [kGladysMainFilter: newFilter]
        } else {
            userInfo![kGladysMainFilter] = newFilter
        }
        return newFilter
    }
}

extension UIView {
    var associatedFilter: Filter? {
        let w = (self as? UIWindow) ?? window
        return w?.windowScene?.session.associatedFilter
    }
}

extension Model {
    private static var saveOverlap = 0
    private static var registeredForBackground = false

    private static var watchDelegate: WatchDelegate?
    
    static func registerStateHandler() {
        stateHandler = { state in
            switch state {
            case .migrated:
                clearLegacyIntents()

            case .indexSaveComplete:
                saveDone()

            case .saveComplete:
                saveOverlap -= 1
                if saveOverlap > 0 {
                    return
                }
                saveDone()

            case .willSave:
                saveOverlap += 1
                if !registeredForBackground {
                    registeredForBackground = true
                    BackgroundTask.registerForBackground()
                }

            case .startupComplete:
                trimTemporaryDirectory()
                if WCSession.isSupported() {
                    watchDelegate = WatchDelegate()
                }
            }
        }
    }

    private static func saveDone() {
        if let wd = watchDelegate {
            Task {
                await wd.updateContext()
            }
        }

        Task {
            do {
                if try await resyncIfNeeded() {
                    try await CloudManager.syncAfterSaveIfNeeded()
                }
            } catch {
                log("Error in sync after save: \(error.finalDescription)")
            }
        }

        if registeredForBackground {
            registeredForBackground = false
            BackgroundTask.unregisterForBackground()
        }
    }

    @discardableResult
    static func pasteItems(from providers: [NSItemProvider], overrides: ImportOverrides?) -> PasteResult {
        if providers.isEmpty {
            return .noData
        }

        let currentFilter = currentWindow?.associatedFilter

        var items = [ArchivedItem]()
        var addedStuff = false
        for provider in providers { // separate item for each provider in the pasteboard
            for item in ArchivedItem.importData(providers: [provider], overrides: overrides) {
                if let currentFilter, currentFilter.isFilteringLabels, !PersistedOptions.dontAutoLabelNewItems {
                    item.labels = currentFilter.enabledLabelsForItems
                }
                DropStore.insert(drop: item, at: 0)
                items.append(item)
                addedStuff = true
            }
        }

        if addedStuff {
            _ = currentFilter?.update(signalUpdate: .animated)
        }

        return .success(items)
    }

    static var pasteIntent: PasteClipboardIntent {
        let intent = PasteClipboardIntent()
        intent.suggestedInvocationPhrase = "Paste in Gladys"
        return intent
    }

    private static func clearLegacyIntents() {
        if #available(iOS 16, *) {
            INInteraction.deleteAll() // using app intents now
        }
    }

    static func donatePasteIntent() {
        if #available(iOS 16, *) {
            log("Will not donate SiriKit paste shortcut")
        } else {
            let interaction = INInteraction(intent: pasteIntent, response: nil)
            interaction.identifier = "paste-in-gladys"
            interaction.donate { error in
                if let error {
                    log("Error donating paste shortcut: \(error.localizedDescription)")
                } else {
                    log("Donated paste shortcut")
                }
            }
        }
    }
}
