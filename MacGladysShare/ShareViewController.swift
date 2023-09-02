import AppKit
import GladysCommon
import Minions

final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? {
        NSNib.Name("ShareViewController")
    }

    @IBOutlet private var spinner: NSProgressIndicator!
    @IBOutlet private var cancelButton: NSButton!
    @IBOutlet private var status: NSTextField!

    private var cancelled = false
    private var progresses = [Progress]()
    private let importGroup = DispatchGroup()
    private let pasteboard = NSPasteboard(name: sharingPasteboard)
    private var pasteboardItems = [NSPasteboardWriting]()

    @IBAction private func cancelButtonSelected(_: NSButton) {
        cancelled = true
        for p in progresses where !p.isFinished {
            p.cancel()
            importGroup.leave()
        }
        progresses.removeAll()
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        importGroup.enter() // released after load
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        importGroup.enter() // released after load
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(pasteDone), name: .SharingPasteboardPasted, object: "build.bru.MacGladys")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        status.stringValue = "Loading data…"
        spinner.startAnimation(nil)
        pasteboardItems.removeAll()

        guard let extensionContext else { return }

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
            for attachment in attachments {
                let newItem = NSPasteboardItem()
                pasteboardItems.append(newItem)
                var identifiers = attachment.registeredTypeIdentifiers
                if identifiers.contains("public.file-url"), identifiers.contains("public.url") { // finder is sharing
                    log("> Removing Finder redundant URL data")
                    identifiers.removeAll { $0 == "public.file-url" || $0 == "public.url" }
                }
                log("> Ingesting data with identifiers: \(identifiers.joined(separator: ", "))")
                for type in identifiers {
                    importGroup.enter()
                    let p = attachment.loadDataRepresentation(forTypeIdentifier: type, completionHandler: #weakSelf { data, _ in
                        if let data {
                            newItem.setData(data, forType: NSPasteboard.PasteboardType(type))
                        }
                        importGroup.leave()
                    })
                    progresses.append(p)
                }
            }
        }

        importGroup.leave() // from the one in awakeFromNib
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard let extensionContext else { return }

        importGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self else { return }

            if cancelled {
                let error = GladysError.actionCancelled
                log(error.localizedDescription)
                extensionContext.cancelRequest(withError: error)
                return
            }

            log("Writing data to parent app…")
            cancelButton.isHidden = true
            pasteboard.clearContents()
            pasteboard.writeObjects(pasteboardItems)
            status.stringValue = "Saving…"
            if !NSWorkspace.shared.open(URL(string: "gladys://x-callback-url/paste-share-pasteboard")!) {
                let error = GladysError.mainAppFailedToOpen
                log(error.localizedDescription)
                extensionContext.cancelRequest(withError: error)
            }
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func pasteDone() {
        log("Main app ingest done.")
        status.stringValue = "Done"
        pasteboard.clearContents()
        spinner.stopAnimation(nil)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
