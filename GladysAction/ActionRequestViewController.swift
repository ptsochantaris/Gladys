import GladysCommon
import UIKit

extension Notification.Name {
    static let DoneSelected = Notification.Name("DoneSelected")
}

final class ActionRequestViewController: UIViewController {
    @IBOutlet private var statusLabel: UILabel!
    @IBOutlet private var cancelButton: UIBarButtonItem!
    @IBOutlet private var image: UIImageView!
    @IBOutlet private var spinner: UIActivityIndicatorView!
    @IBOutlet private var check: UIImageView!

    private var loadCount = 0
    private var ingestOnWillAppear = true
    private var newItems = [ArchivedItem]()

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(done), name: .DoneSelected, object: nil)
        ingest()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if ingestOnWillAppear {
            ingest()
        }
    }

    private var newTotal: Int {
        Model.countSavedItemsWithoutLoading() + loadCount
    }

    private func error(text: String) {
        statusLabel.isHidden = false
        statusLabel.text = text
        spinner.stopAnimating()
    }

    private func ingest() {
        reset(ingestOnNextAppearance: false) // resets everything

        showBusy(true)
        loadCount = extensionContext?.inputItems.count ?? 0

        if loadCount == 0 {
            error(text: "There don't seem to be any importable items offered by this app.")
            return
        }

        var inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        if inputItems.count == 2 {
            // Special Safari behaviour, adds weird 2nd URL, let's remove it
            var count = 0
            var hasSafariFlag = false
            var weirdIndex: Int?
            var index = 0
            for item in inputItems {
                if item.attachments?.count == 1, let provider = item.attachments?.first, provider.registeredTypeIdentifiers.count == 1, provider.registeredTypeIdentifiers.first == "public.url" {
                    count += 1
                    if item.userInfo?["supportsJavaScript"] as? Int == 1 {
                        hasSafariFlag = true
                    } else {
                        weirdIndex = index
                    }
                }
                index += 1
            }
            // If all are URLs, find the weird link, if any, and trim it
            if count == inputItems.count, hasSafariFlag, let weirdIndex {
                inputItems.remove(at: weirdIndex)
            }
        }

        let providerList = inputItems.reduce([]) { list, inputItem -> [NSItemProvider] in
            if let attachments = inputItem.attachments {
                return list + attachments
            } else {
                return list
            }
        }

        var allDifferentTypes = true
        var typeSet = Set<String>()
        for p in providerList {
            let currentTypes = Set(p.registeredTypeIdentifiers)
            if typeSet.isDisjoint(with: currentTypes) {
                typeSet.formUnion(currentTypes)
            } else {
                allDifferentTypes = false
                break
            }
        }

        if allDifferentTypes { // posibly this is a composite item, leave it up to the user's settings
            for newItem in ArchivedItem.importData(providers: providerList, overrides: nil) {
                newItems.append(newItem)
            }
        } else { // list of items shares common types, let's assume they are multiple items per provider
            for provider in providerList {
                for newItem in ArchivedItem.importData(providers: [provider], overrides: nil) {
                    newItems.append(newItem)
                }
            }
        }
    }

    private func showBusy(_ busy: Bool) {
        check.isHidden = busy
        if busy {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    @IBAction private func cancelRequested(_: UIBarButtonItem) {
        newItems.forEach { $0.cancelIngest() }
        reset(ingestOnNextAppearance: true)
        extensionContext?.cancelRequest(withError: GladysError.actionCancelled.error)
    }

    @objc private func itemIngested(_ notification: Notification) {
        if let item = notification.object as? ArchivedItem {
            for label in item.labels where !ActionRequestViewController.labelsToApply.contains(label) {
                ActionRequestViewController.labelsToApply.append(label)
            }
        }

        guard Model.doneIngesting else {
            return
        }

        showBusy(false)
        check.transform = CGAffineTransform(scaleX: 0.33, y: 0.33)
        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.33, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1, options: .curveEaseOut) {
            self.check.transform = CGAffineTransform(scaleX: 1, y: 1)
        } completion: { _ in
            if PersistedOptions.setLabelsWhenActioning {
                if self.navigationController?.viewControllers.count == 1 {
                    self.performSegue(withIdentifier: "showLabelsAndNotes", sender: nil)
                }
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
                    self.signalDone()
                }
            }
        }
    }

    private func reset(ingestOnNextAppearance: Bool) {
        statusLabel.isHidden = true
        if PersistedOptions.setLabelsWhenActioning {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Note & Labels", primaryAction: UIAction { [weak self] _ in self?.performSegue(withIdentifier: "showLabelsAndNotes", sender: nil) })
        } else {
            navigationItem.rightBarButtonItem = nil
        }
        showBusy(false)

        ingestOnWillAppear = ingestOnNextAppearance
        newItems.removeAll()
        ActionRequestViewController.labelsToApply.removeAll()
        ActionRequestViewController.noteToApply = ""
        Model.reset()
    }

    @objc private func signalDone() {
        sendNotification(name: .DoneSelected, object: nil)
    }

    @objc private func done() {
        for item in newItems {
            item.labels = ActionRequestViewController.labelsToApply
            item.note = ActionRequestViewController.noteToApply
        }

        Model.insertNewItemsWithoutLoading(items: newItems, addToDrops: true)

        Task {
            await CloudManager.signalExtensionUpdate()
        }

        dismiss(animated: true) {
            self.reset(ingestOnNextAppearance: true)
            self.extensionContext?.completeRequest(returningItems: nil) { _ in
                log("Dismissed")
            }
        }
    }

    ////////////////////// Labels

    static var labelsToApply = [String]()
    static var noteToApply = ""
}
