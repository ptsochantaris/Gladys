import CallbackURLKit
import GladysCommon
import GladysUI
import UIKit
import UniformTypeIdentifiers

extension CallbackSupport {
    private static func handle(result: PasteResult, success: @escaping SuccessCallback, failure: @escaping FailureCallback) {
        Task {
            try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
            switch result {
            case .success:
                success(nil)
            case .noData:
                failure(NSError.error(code: 1, failureReason: "Clipboard is empty."))
            }
        }
    }

    static func setupCallbackSupport() {
        let m = Manager.shared
        m.callbackURLScheme = Manager.urlSchemes?.first

        m["paste-clipboard"] = { parameters, success, failure, _ in
            let result = handlePasteRequest(title: parameters["title"], note: parameters["note"], labels: parameters["labels"])
            handle(result: result, success: success, failure: failure)
        }

        m["create-item"] = { parameters, success, failure, _ in
            let importOverrides = createOverrides(from: parameters)

            if let text = parameters["text"] as NSString? {
                let result = handleCreateRequest(object: text, overrides: importOverrides)
                handle(result: result, success: success, failure: failure)

            } else if let text = parameters["url"] {
                if let url = URL(string: text) {
                    let result = handleCreateRequest(object: url as NSURL, overrides: importOverrides)
                    handle(result: result, success: success, failure: failure)

                } else {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
                        failure(NSError.error(code: 4, failureReason: "Invalid URL."))
                    }
                }

            } else if let text = parameters["base64data"] as String? {
                if let data = Data(base64Encoded: text) {
                    let result = handleEncodedRequest(data, overrides: importOverrides)
                    handle(result: result, success: success, failure: failure)

                } else {
                    failure(NSError.error(code: 5, failureReason: "Could not decode base64 data string."))
                }

            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
                    failure(NSError.error(code: 3, failureReason: "One of 'text', 'url', or 'base64data' parameters is required."))
                }
            }
        }
    }

    @discardableResult
    static func handleEncodedRequest(_ data: Data, overrides: ImportOverrides) -> PasteResult {
        let importer = DataImporter(type: UTType.data.identifier, data: data, suggestedName: overrides.title)
        return Model.pasteItems(from: [importer], overrides: overrides, currentFilter: nil)
    }

    @discardableResult
    static func handlePasteRequest(title: String?, note: String?, labels: String?) -> PasteResult {
        sendNotification(name: .DismissPopoversRequest)

        let labelsList = labels?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let importOverrides = ImportOverrides(title: title, note: note, labels: labelsList)
        let importers = UIPasteboard.general.itemProviders.map { DataImporter(itemProvider: $0) }
        return Model.pasteItems(from: importers, overrides: importOverrides, currentFilter: nil)
    }

    @discardableResult
    private static func handleCreateRequest(object: NSItemProviderWriting, overrides: ImportOverrides) -> PasteResult {
        let p = NSItemProvider(object: object)
        let importer = DataImporter(itemProvider: p)
        return Model.pasteItems(from: [importer], overrides: overrides, currentFilter: nil)
    }
}
