import AppKit
import CallbackURLKit
import Foundation
import UniformTypeIdentifiers
import GladysCommon

@MainActor
enum CallbackSupport {
    private static func handle(result: PasteResult, success: @escaping SuccessCallback, failure: @escaping FailureCallback) async {
        try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
        switch result {
        case .success:
            success(nil)
        case .noData:
            failure(NSError.error(code: 1, failureReason: "Items could not be added."))
        }
    }

    static func setupCallbackSupport() {
        let m = Manager.shared
        m.callbackURLScheme = Manager.urlSchemes?.first

        m["paste-clipboard"] = { parameters, success, failure, _ in
            Task {
                let result = handlePasteRequest(title: parameters["title"], note: parameters["note"], labels: parameters["labels"])
                await handle(result: result, success: success, failure: failure)
            }
        }

        m["create-item"] = { parameters, success, failure, _ in
            let importOverrides = createOverrides(from: parameters)

            if let text = parameters["text"] as NSString? {
                Task {
                    let result = handleCreateRequest(object: text, overrides: importOverrides)
                    await handle(result: result, success: success, failure: failure)
                }
            } else if let text = parameters["url"] {
                if let url = URL(string: text) {
                    Task {
                        let result = handleCreateRequest(object: url as NSURL, overrides: importOverrides)
                        await handle(result: result, success: success, failure: failure)
                    }
                } else {
                    Task {
                        try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
                        failure(NSError.error(code: 4, failureReason: "Invalid URL."))
                    }
                }

            } else if let text = parameters["base64data"] as String? {
                if let data = Data(base64Encoded: text) {
                    Task {
                        let result = handleEncodedRequest(data, overrides: importOverrides)
                        await handle(result: result, success: success, failure: failure)
                    }
                } else {
                    failure(NSError.error(code: 5, failureReason: "Could not decode base64 data string."))
                }

            } else {
                Task {
                    try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
                    failure(NSError.error(code: 3, failureReason: "One of 'text', 'url', or 'base64data' parameters is required."))
                }
            }
        }

        m["paste-share-pasteboard"] = { parameters, success, _, _ in
            let importOverrides = createOverrides(from: parameters)
            let pasteboard = NSPasteboard(name: sharingPasteboard)
            Task {
                _ = Model.addItems(from: pasteboard, at: IndexPath(item: 0, section: 0), overrides: importOverrides, filterContext: nil)
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                DistributedNotificationCenter.default().postNotificationName(.SharingPasteboardPasted, object: "build.bru.MacGladys", userInfo: nil, deliverImmediately: true)
            }
            success(nil)
        }
    }

    @discardableResult
    static func handleEncodedRequest(_ data: Data, overrides: ImportOverrides) -> PasteResult {
        let p = NSItemProvider()
        p.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion -> Progress? in
            completion(data, nil)
            return nil
        }
        return Model.addItems(itemProviders: [p], indexPath: IndexPath(item: 0, section: 0), overrides: overrides, filterContext: nil)
    }

    @discardableResult
    static func handlePasteRequest(title: String?, note: String?, labels: String?) -> PasteResult {
        let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
        return Model.addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: importOverrides, filterContext: nil)
    }

    @discardableResult
    static func handleCreateRequest(object: NSItemProviderWriting, overrides: ImportOverrides) -> PasteResult {
        let p = NSItemProvider(object: object)
        return Model.addItems(itemProviders: [p], indexPath: IndexPath(item: 0, section: 0), overrides: overrides, filterContext: nil)
    }
}
