import AppKit
import GladysCommon

@MainActor
final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? {
        NSNib.Name("ShareViewController")
    }

    @IBOutlet private var spinner: NSProgressIndicator!
    @IBOutlet private var cancelButton: NSButton!
    @IBOutlet private var status: NSTextField!

    private var importTask: Task<Void, Never>?
    private var progresses = [Progress]()
    private let pasteboard = NSPasteboard(name: sharingPasteboard)

    @IBAction private func cancelButtonSelected(_: NSButton) {
        importTask?.cancel()
        for p in progresses where !p.isFinished {
            p.cancel()
        }
        progresses.removeAll()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(pasteDone), name: .SharingPasteboardPasted, object: "build.bru.MacGladys")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        importTask = Task {
            do {
                try await runImport()
            } catch {
                done(error: error)
            }
        }
    }

    private func runImport() async throws {
        guard let extensionContext else { return }

        status.stringValue = "Loading data…"
        spinner.startAnimation(nil)

        var pasteboardItems = [NSPasteboardWriting]()

        for inputItem in extensionContext.inputItems as? [NSExtensionItem] ?? [] {
            var attachments = inputItem.attachments ?? []

            if attachments.count == 2, // detect Safari PDF preview getting attached
               attachments[0].registeredTypeIdentifiers == ["public.url"],
               attachments[1].registeredTypeIdentifiers == ["com.adobe.pdf"] {
                log("Safari PDF found, stripping it")
                attachments.removeAll { $0.registeredTypeIdentifiers == ["com.adobe.pdf"] }
            }

            if attachments.isEmpty { // use the legacy fields
                if let text = inputItem.attributedContentText {
                    log("Ingesting inputItem with text: [\(text.string)]")
                    pasteboardItems.append(text)

                } else if let title = inputItem.attributedTitle {
                    log("Ingesting inputItem with title: [\(title.string)]")
                    pasteboardItems.append(title)
                }
            }

            log("Ingesting inputItem with \(attachments.count) attachment(s)…")
            for attachment in attachments where !Task.isCancelled {
                let newItem = NSPasteboardItem()
                var identifiers = attachment.registeredTypeIdentifiers
                if identifiers.contains("public.file-url"), identifiers.contains("public.url") { // finder is sharing
                    log("> Removing Finder redundant URL data")
                    identifiers.removeAll { $0 == "public.file-url" || $0 == "public.url" }
                }
                log("> Ingesting data with identifiers: \(identifiers.joined(separator: ", "))")
                for type in identifiers where !Task.isCancelled {
                    let data = await withCheckedContinuation { continuation in
                        let p = attachment.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                            continuation.resume(returning: data)
                        }
                        progresses.append(p)
                    }
                    if let data {
                        newItem.setData(data, forType: NSPasteboard.PasteboardType(type))
                    }
                }
                pasteboardItems.append(newItem)
            }

            if Task.isCancelled {
                throw GladysError.actionCancelled
            }

            log("Writing data to parent app…")
            cancelButton.isHidden = true
            pasteboard.clearContents()
            pasteboard.writeObjects(pasteboardItems)
            status.stringValue = "Saving…"

            if !NSWorkspace.shared.open(URL(string: "gladys://x-callback-url/paste-share-pasteboard")!) {
                throw GladysError.mainAppFailedToOpen
            }
        }
    }

    private func done(error: Error?) {
        spinner.stopAnimation(nil)
        pasteboard.clearContents()
        importTask = nil
        progresses.removeAll()

        if let error {
            log(error.localizedDescription)
            extensionContext?.cancelRequest(withError: error)
        } else {
            log("Main app ingest done.")
            status.stringValue = "Done"
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    @objc private func pasteDone() {
        done(error: nil)
    }
}
