import CloudKit
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

protocol ResizingCellDelegate: AnyObject {
    func cellNeedsResize(cell: UITableViewCell, caretRect: CGRect?, heightChange: Bool)
}

final class DetailController: GladysViewController,
    UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate,
    UIPopoverPresentationControllerDelegate, AddLabelControllerDelegate, TextEditControllerDelegate,
    ResizingCellDelegate, DetailCellDelegate {
    var item: ArchivedItem!
    var sourceIndexPath: IndexPath?

    private var showTypeDetails = false

    @IBOutlet private var table: UITableView!
    @IBOutlet private var openButton: UIBarButtonItem!
    @IBOutlet private var dateLabel: UILabel!
    @IBOutlet private var dateLabelHolder: UIView!
    @IBOutlet private var menuButton: UIBarButtonItem?

    override func viewDidLoad() {
        super.viewDidLoad()

        doneButtonLocation = .right
        windowButtonLocation = .right
        
        table.estimatedRowHeight = UITableView.automaticDimension
        table.rowHeight = UITableView.automaticDimension
        table.dragInteractionEnabled = true
        table.dragDelegate = self
        table.dropDelegate = self
        table.allowsFocus = true
        table.remembersLastFocusedIndexPath = true
        table.focusGroupIdentifier = "build.bru.gladys.detail.focus"

        openButton.isEnabled = item.canOpen

        dateLabel.text = item.addedString
        navigationItem.titleView = dateLabelHolder

        isReadWrite = item.shareMode != .elsewhereReadOnly
        
        userActivity = NSUserActivity(activityType: kGladysDetailViewingActivity)
        userActivity?.needsSave = true

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(keyboardHiding(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        n.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        n.addObserver(self, selector: #selector(dataUpdate(_:)), name: .ModelDataUpdated, object: nil)
        n.addObserver(self, selector: #selector(updateUI), name: .ItemModified, object: item)
        n.addObserver(self, selector: #selector(updateUI), name: .IngestComplete, object: item)
        
        colorButton.changesSelectionAsPrimaryAction = true
    }
    
    private let colorButton = UIBarButtonItem()
    
    private func setupColorPicker() {
        let currentColor = item.highlightColor
        let children = ItemColor.allCases.map { color in
            UIAction(title: color.title, image: color.img, state: (currentColor == color) ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.item.highlightColor = color
                self.makeIndexAndSaveItem()
            }
        }
        colorButton.menu = UIMenu(title: "Highlight Color", options: .singleSelection, children: children)
        if var items = navigationItem.rightBarButtonItems {
            if let buttonIndex = items.firstIndex(of: colorButton) {
                if buttonIndex < (items.count - 1) {
                    let button = items.remove(at: buttonIndex)
                    items.append(button)
                    navigationItem.rightBarButtonItems = items
                } else {
                    // nothing
                }
            } else {
                items.append(colorButton)
                navigationItem.rightBarButtonItems = items
            }
        } else {
            navigationItem.rightBarButtonItems = [colorButton]
        }
    }
    
    override func updateButtons(newTraitCollection: UITraitCollection) {
        super.updateButtons(newTraitCollection: newTraitCollection)
        setupColorPicker()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let m = menuButton, presentingViewController == nil,
           let i = navigationItem.leftBarButtonItems?.firstIndex(of: m) {
            navigationItem.leftBarButtonItems?.remove(at: i)
            menuButton = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateMenuButton()
    }

    private func updateMenuButton() {
        if let m = menuButton, let v = view.window?.windowScene?.mainController, let sourceIndexPath {
            m.menu = v.createShortcutActions(for: item, mainView: false, indexPath: sourceIndexPath)
        }
    }

    @objc private func dataUpdate(_ notification: Notification) {
        if item == nil || item?.needsDeletion == true {
            done()
        } else if let uuid = item?.uuid, let removedUUIDs = (notification.object as? [AnyHashable: Any])?["removed"] as? Set<UUID>, removedUUIDs.contains(uuid) {
            done()
        } else {
            updateUI()
        }
    }

    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        if let item { // check for very weird corner case where item may be nil
            ArchivedItem.updateUserActivity(activity, from: item, child: nil, titled: "Info of")
        }
    }

    @objc private func updateUI() {
        view.endEditing(true)
        if item == nil {
            done()
            return
        }

        // second pass, ensure item is fresh
        item = Model.item(uuid: item.uuid)
        if item == nil || item?.needsDeletion == true {
            done()
        } else {
            isReadWrite = item.shareMode != .elsewhereReadOnly
            updateMenuButton()
            view.setNeedsLayout()
            table.reloadData()
            sizeWindow()
        }
    }

    var isReadWrite = false {
        didSet {
            table.allowsSelection = isReadWrite
            table.dragInteractionEnabled = isReadWrite
            navigationController?.isToolbarHidden = isReadWrite
            hidesBottomBarWhenPushed = isReadWrite
        }
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        var a = super.keyCommands ?? []
        a.append(contentsOf: [
            UIKeyCommand.makeCommand(input: "o", modifierFlags: [.command], action: #selector(openKeySelected), title: "Open Item"),
            UIKeyCommand.makeCommand(input: "t", modifierFlags: [.command], action: #selector(topSelected), title: "Move Item To Top"),
            UIKeyCommand.makeCommand(input: "d", modifierFlags: [.command], action: #selector(duplicateSelected), title: "Duplicate Item"),
            UIKeyCommand.makeCommand(input: "c", modifierFlags: [.command], action: #selector(copySelected), title: "Copy Item To Clipboard"),
            UIKeyCommand.makeCommand(input: "x", modifierFlags: [.command], action: #selector(cutSelected), title: "Cut Item To Clipboard"),
            UIKeyCommand.makeCommand(input: "\u{08}", modifierFlags: [.command, .shift], action: #selector(deleteSelected), title: "Delete Item")
        ])
        return a
    }

    @objc private func openKeySelected() {
        if openButton.isEnabled {
            openSelected(openButton)
        }
    }

    @objc private func topSelected() {
        done()
        Model.sendToTop(items: [item])
    }

    @objc private func duplicateSelected() {
        done()
        Model.duplicate(item: item)
    }

    @objc private func cutSelected() {
        item.copyToPasteboard()
        deleteSelected()
    }

    @objc private func deleteSelected() {
        done()
        Model.delete(items: [item])
    }

    @objc private func copySelected() {
        item.copyToPasteboard()
        Task {
            await genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
        }
    }

    @objc private func keyboardHiding(_ notification: Notification) {
        if let u = notification.userInfo, let previousState = u[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect, !previousState.isEmpty {
            view.endEditing(false)
        }
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo, let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

        let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
        let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 0, dy: -additionalSafeAreaInsets.bottom)
        let intersection = safeAreaFrame.intersection(keyboardFrameInView)
        additionalSafeAreaInsets.bottom = intersection.height
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { // workaround for quiclook dismissal issue
            if let n = self.navigationController {
                if n.viewControllers.count > 1 {
                    n.popViewController(animated: false)
                }
            }
            completion?()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed ?? false {
            sendNotification(name: .DetailViewClosing, object: nil)
        }
    }

    private var sizing = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if firstAppearance {
            sizeWindow()
        }
    }

    private func sizeWindow() {
        if sizing { return }
        sizing = true
        table.layoutIfNeeded()
        let preferredSize = CGSize(width: 320, height: table.contentSize.height)
        popoverPresentationController?.presentedViewController.preferredContentSize = preferredSize
        log("Detail view preferred size set to \(preferredSize)")
        sizing = false
    }

    @IBAction private func openSelected(_: UIBarButtonItem) {
        item.tryOpen(in: navigationController!) { shouldClose in
            if shouldClose {
                self.done()
            }
        }
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2
        case 1: return item.labels.count + 1
        case 2: return item.components.count
        default: return 0 // WTF :)
        }
    }

    func numberOfSections(in _: UITableView) -> Int {
        if item == nil || item?.needsDeletion == true {
            return 0
        }
        return item.components.isEmpty ? 2 : 3
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1: return "Labels"
        case 2: return "Components"
        default: return nil
        }
    }

    func cellNeedsResize(cell: UITableViewCell, caretRect: CGRect?, heightChange: Bool) {
        if heightChange {
            UIView.performWithoutAnimation {
                table.beginUpdates()
                table.endUpdates()
                sizeWindow()
            }
        }
        if let caretRect {
            table.scrollRectToVisible(caretRect, animated: false)
        } else if let section = table.indexPath(for: cell)?.section {
            table.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath) as! HeaderCell
                cell.item = item
                cell.isUserInteractionEnabled = isReadWrite
                cell.delegate = self
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as! NoteCell
                cell.item = item
                cell.isUserInteractionEnabled = isReadWrite
                cell.delegate = self
                return cell
            }

        } else if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath) as! LabelCell
            if indexPath.row < item.labels.count {
                cell.label = item.labels[indexPath.row]
            } else {
                cell.label = nil
            }
            return cell

        } else {
            let component = item.components[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath) as! DetailCell
            cell.configure(with: component, showTypeDetails: showTypeDetails, isReadWrite: isReadWrite, delegate: self)
            return cell
        }
    }

    func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        if indexPath.section == 1 {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                if indexPath.row >= self.item.labels.count { return nil }
                let text = self.item.labels[indexPath.row]

                var children = [
                    UIAction(title: "Copy to Clipboard", image: UIImage(systemName: "doc.on.doc")) { _ in
                        UIPasteboard.general.string = text
                        Task {
                            await genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
                        }
                    }
                ]

                if UIApplication.shared.supportsMultipleScenes, let scene = self.view.window?.windowScene {
                    children.insert(UIAction(title: "Open in Window", image: UIImage(systemName: "uiwindow.split.2x1")) { _ in
                        Filter.Toggle.Function.userLabel(text).openInWindow(from: scene)
                    }, at: 1)
                }

                if self.isReadWrite {
                    children.append(UIAction(title: "Remove", image: UIImage(systemName: "xmark"), attributes: .destructive) { _ in
                        self.removeLabel(text)
                    })
                }

                return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
            }

        } else if indexPath.section == 2 {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let component = self.item.components[indexPath.row]

                var children = [
                    UIAction(title: "Copy to Clipboard", image: UIImage(systemName: "doc.on.doc")) { _ in
                        component.copyToPasteboard()
                        Task {
                            await genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
                        }
                    },

                    UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                        guard let s = self, let cell = s.table.cellForRow(at: indexPath) else { return }
                        let a = UIActivityViewController(activityItems: [component.sharingActivitySource], applicationActivities: nil)
                        if let p = a.popoverPresentationController {
                            p.sourceView = cell
                            p.sourceRect = cell.bounds.insetBy(dx: cell.bounds.width * 0.2, dy: cell.bounds.height * 0.2)
                        }
                        s.present(a, animated: true)
                        if let p = a.popoverPresentationController {
                            p.sourceView = cell
                            p.sourceRect = cell.bounds.insetBy(dx: cell.bounds.width * 0.2, dy: cell.bounds.height * 0.2)
                        }
                    }
                ]

                if component.canOpen {
                    children.insert(UIAction(title: "Open", image: UIImage(systemName: "arrow.up.doc")) { [weak self] _ in
                        guard let n = self?.navigationController else { return }
                        component.tryOpen(in: n)
                    }, at: 0)
                }

                if component.parent?.shareMode != .elsewhereReadOnly {
                    children.append(UIAction(title: "Delete", image: UIImage(systemName: "bin.xmark"), attributes: .destructive) { _ in
                        self.removeComponent(component)
                    })
                }

                return UIMenu(title: component.typeIdentifier, image: nil, identifier: nil, options: [], children: children)
            }

        } else {
            return nil
        }
    }

    private func component(for cell: DetailCell) -> Component? {
        if let ip = table.indexPath(for: cell) {
            return item.components[ip.row]
        }
        return nil
    }

    func inspectOptionSelected(in cell: DetailCell) {
        guard let component = component(for: cell) else { return }
        if component.isPlist {
            let a = UIAlertController(title: "Inspect", message: "This item can be viewed as a property-list.", preferredStyle: .actionSheet)
            a.addAction(UIAlertAction(title: "Property List View", style: .default) { _ in
                self.performSegue(withIdentifier: "plistEdit", sender: component)
            })
            a.addAction(UIAlertAction(title: "Raw Data View", style: .default) { _ in
                self.performSegue(withIdentifier: "hexEdit", sender: component)
            })
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            if let p = a.popoverPresentationController {
                p.sourceView = cell.inspectButton
                p.sourceRect = cell.inspectButton.bounds
            }
            present(a, animated: true)
        } else {
            performSegue(withIdentifier: "hexEdit", sender: component)
        }
    }

    func editOptionSelected(in cell: DetailCell) {
        guard let component = component(for: cell) else { return }
        if component.encodedUrl != nil {
            editURL(component, existingEdit: nil)
        } else if component.isText {
            performSegue(withIdentifier: "textEdit", sender: component)
        }
    }

    func viewOptionSelected(in cell: DetailCell) {
        guard let component = component(for: cell), let q = component.quickLook() else { return }
        if phoneMode || !PersistedOptions.fullScreenPreviews {
            navigationController?.pushViewController(q, animated: true)

        } else if let presenter = view.window?.alertPresenter {
            let nav = GladysNavController(rootViewController: q)
            nav.modalPresentationStyle = .overFullScreen
            nav.sourceItemView = cell
            presenter.present(nav, animated: true)
        }
    }

    func archiveOptionSelected(in cell: DetailCell) {
        guard let component = component(for: cell), let url = component.encodedUrl else { return }
        archiveWebComponent(cell: cell, url: url as URL)
    }

    private func editURL(_ component: Component, existingEdit: String?) {
        Task {
            let newValue = await getInput(from: self, title: "Edit URL", action: "Change", previousValue: existingEdit ?? component.encodedUrl?.absoluteString)
            if let newValue, let newURL = URL(string: newValue), let scheme = newURL.scheme, !scheme.isEmpty {
                component.replaceURL(newURL)
                item.needsReIngest = true
                makeIndexAndSaveItem()
                refreshComponent(component)
            } else if let newValue {
                await genericAlert(title: "This is not a valid URL", message: newValue)
                editURL(component, existingEdit: newValue)
            }
        }
    }

    private var shouldWaitForSync: Bool {
        CloudManager.syncing || item.needsReIngest || item.isTransferring
    }

    private func afterSync() async {
        guard shouldWaitForSync else { return }

        var keepChecking = true
        var alert: UIAlertController?
        Task {
            await genericAlert(title: "Syncing last update", message: "One moment please…", buttonTitle: "Cancel", alertController: { alert = $0 })
            keepChecking = false
        }

        while keepChecking {
            try? await Task.sleep(nanoseconds: 25 * NSEC_PER_MSEC)
            if !shouldWaitForSync {
                keepChecking = false
                await alert?.dismiss(animated: true)
            }
        }
    }

    private func removeLabel(_ label: String) {
        Task {
            await afterSync()
            _removeLabel(label)
        }
    }

    private func _removeLabel(_ label: String) {
        table.performBatchUpdates({
            guard let index = item.labels.firstIndex(of: label) else {
                return
            }
            item.labels.remove(at: index)
            let indexPath = IndexPath(row: index, section: 1)
            table.deleteRows(at: [indexPath], with: .automatic)
        }, completion: { _ in
            self.makeIndexAndSaveItem()
            UIAccessibility.post(notification: .layoutChanged, argument: self.table)
        })
    }

    private func removeComponent(_ component: Component) {
        Task {
            await afterSync()
            _removeComponent(component)
        }
    }

    private func _removeComponent(_ component: Component) {
        table.performBatchUpdates({
            guard let index = item.components.firstIndex(of: component) else {
                return
            }
            component.deleteFromStorage()
            item.components.remove(at: index)
            if item.components.isEmpty {
                table.deleteSections(IndexSet(integer: 2), with: .automatic)
            } else {
                let indexPath = IndexPath(row: index, section: 2)
                table.deleteRows(at: [indexPath], with: .automatic)
            }
        }, completion: { _ in
            self.item.renumberTypeItems()
            self.item.needsReIngest = true
            self.makeIndexAndSaveItem()
        })
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "textEdit",
           let typeEntry = sender as? Component,
           let e = segue.destination as? TextEditController {
            e.item = item
            e.typeEntry = typeEntry
            e.delegate = self

        } else if segue.identifier == "hexEdit",
                  let typeEntry = sender as? Component,
                  let e = segue.destination as? HexEdit {
            e.bytes = typeEntry.bytes ?? emptyData

            let f = ByteCountFormatter()
            let size = f.string(fromByteCount: Int64(e.bytes.count))
            e.title = typeEntry.typeDescription + " (\(size))"

        } else if segue.identifier == "plistEdit",
                  let typeEntry = sender as? Component,
                  let e = segue.destination as? PlistEditor,
                  let b = typeEntry.bytes,
                  let propertyList = try? PropertyListSerialization.propertyList(from: b, options: [], format: nil) {
            e.title = typeEntry.trimmedName
            e.propertyList = propertyList

        } else if segue.identifier == "addLabel",
                  let indexPath = sender as? IndexPath,
                  let n = segue.destination as? UINavigationController,
                  let p = n.popoverPresentationController,
                  let d = n.topViewController as? AddLabelController {
            if let cell = table.cellForRow(at: indexPath) {
                p.sourceView = cell
                p.sourceRect = cell.bounds.insetBy(dx: 30, dy: 15)
            }
            p.permittedArrowDirections = [.left, .right]
            d.delegate = self
            d.exclude = Set(item.labels)
            d.modelFilter = view.associatedFilter
            p.delegate = self
            if indexPath.row < item.labels.count {
                d.title = "Edit Label"
                d.label = item.labels[indexPath.row]
            } else {
                d.title = "Add Label"
            }

        } else if segue.identifier == "toSiriShortcuts",
                  let n = segue.destination as? UINavigationController,
                  let p = n.popoverPresentationController {
            p.delegate = self
            if let m = menuButton {
                p.barButtonItem = m
            }
        }
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0: return 16
        default: return 44
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section == numberOfSections(in: tableView) - 1 {
            return 17
        } else {
            return CGFloat.leastNonzeroMagnitude
        }
    }

    func tableView(_: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        switch indexPath.section {
        case 1:
            if let i = item.dragItem(forLabelIndex: indexPath.row) {
                session.localContext = "label"
                return [i]
            } else {
                return []
            }

        case 2:
            let typeItem = item.components[indexPath.row]
            session.localContext = "typeItem"
            return [typeItem.dragItem]

        default: return []
        }
    }

    func tableView(_: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if let d = destinationIndexPath, let s = session.localDragSession, isReadWrite, !item.shouldDisplayLoading {
            if d.section == 1, d.row < item.labels.count, s.canLoadObjects(ofClass: String.self) {
                if let simpleString = s.items.first?.localObject as? String, item.labels.contains(simpleString) {
                    return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
                }
                return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
            }
            if d.section == 2, let candidate = s.items.first?.localObject as? Component {
                let operationType: UIDropOperation = item.components.contains(candidate) ? .move : .copy
                return UITableViewDropProposal(operation: operationType, intent: .insertAtDestinationIndexPath)
            }
        }
        return UITableViewDropProposal(operation: .cancel)
    }

    func tableView(_: UITableView, dragSessionDidEnd session: UIDragSession) {
        if session.localContext as? String == "typeItem" {
            Singleton.shared.componentDropActiveFromDetailView = nil
        }
    }

    func tableView(_: UITableView, dropSessionDidExit session: UIDropSession) {
        if let session = session.localDragSession {
            if session.localContext as? String == "typeItem" {
                Singleton.shared.componentDropActiveFromDetailView = self
            }
            if !isAccessoryWindow {
                done()
            }
        }
    }

    func tableView(_: UITableView, dropSessionDidEnter session: UIDropSession) {
        if session.localDragSession == nil {
            done()
        }
    }

    private func makeIndexAndSaveItem() {
        item.markUpdated()
        Model.save()
        userActivity?.needsSave = true
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        for coordinatorItem in coordinator.items {
            let dragItem = coordinatorItem.dragItem
            guard let destinationIndexPath = coordinator.destinationIndexPath, let localObject = dragItem.localObject else { continue }

            if let previousIndex = coordinatorItem.sourceIndexPath { // from this table
                if destinationIndexPath.section == 1 {
                    let existingLabel = localObject as? String
                    if previousIndex.section == 1 {
                        tableView.performBatchUpdates({
                            item.labels.remove(at: previousIndex.row)
                            item.labels.insert(existingLabel ?? "…", at: destinationIndexPath.row)
                            tableView.moveRow(at: previousIndex, to: destinationIndexPath)
                        })
                    } else {
                        tableView.performBatchUpdates({
                            item.labels.insert(existingLabel ?? "…", at: destinationIndexPath.row)
                            tableView.insertRows(at: [destinationIndexPath], with: .automatic)
                        })
                    }

                    if existingLabel == nil {
                        _ = dragItem.itemProvider.loadObject(ofClass: String.self) { newLabel, _ in
                            if let newLabel {
                                Task { @MainActor in
                                    self.item.labels[destinationIndexPath.row] = newLabel
                                    tableView.performBatchUpdates({
                                        tableView.reloadRows(at: [destinationIndexPath], with: .automatic)
                                    })
                                    self.makeIndexAndSaveItem()
                                }
                            }
                        }
                    } else {
                        makeIndexAndSaveItem()
                    }

                } else if destinationIndexPath.section == 2, previousIndex.section == 2 {
                    // moving internal type item
                    let destinationIndex = destinationIndexPath.row
                    let sourceItem = item.components[previousIndex.row]
                    table.performBatchUpdates({
                        item.components.remove(at: previousIndex.row)
                        item.components.insert(sourceItem, at: destinationIndex)
                        item.renumberTypeItems()
                        table.moveRow(at: previousIndex, to: destinationIndexPath)
                    }, completion: { _ in
                        self.handleNewTypeItem()
                    })
                }

            } else if let candidate = dragItem.localObject as? Component {
                if destinationIndexPath.section == 1 {
                    // dropping external type item into labels
                    if let text = candidate.displayTitle {
                        tableView.performBatchUpdates({
                            item.labels.insert(text, at: destinationIndexPath.row)
                            tableView.insertRows(at: [destinationIndexPath], with: .automatic)
                        }, completion: { _ in
                            self.makeIndexAndSaveItem()
                        })
                    }

                } else if destinationIndexPath.section == 2 {
                    // dropping external type item into type items
                    tableView.performBatchUpdates({
                        let itemCopy = Component(from: candidate, newParent: item)
                        item.components.insert(itemCopy, at: destinationIndexPath.item)
                        item.renumberTypeItems()
                        tableView.insertRows(at: [destinationIndexPath], with: .automatic)
                    }, completion: { _ in
                        self.handleNewTypeItem()
                    })
                }
            }

            coordinator.drop(dragItem, toRowAt: destinationIndexPath)
        }
    }

    private func dragParameters(for indexPath: IndexPath) -> UIDragPreviewParameters? {
        let cell = table.cellForRow(at: indexPath)!
        let path = UIBezierPath(roundedRect: cell.contentView.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
        let p = UIDragPreviewParameters()
        p.visiblePath = path
        return p
    }

    func tableView(_: UITableView, dragPreviewParametersForRowAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        dragParameters(for: indexPath)
    }

    func tableView(_: UITableView, dropPreviewParametersForRowAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        dragParameters(for: indexPath)
    }

    func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, indexPath.row < item.labels.count else {
            return nil
        }
        let text = item.labels[indexPath.row]
        return UISwipeActionsConfiguration(actions: [
            UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
                self?.removeLabel(text)
                completion(true)
            }
        ])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        view.endEditing(false)

        switch indexPath.section {
        case 0:
            let cell = tableView.cellForRow(at: indexPath)
            if let cell = cell as? HeaderCell {
                cell.startEdit()
            } else if let cell = cell as? NoteCell {
                cell.startEdit()
            }

        case 1:
            Task { @MainActor in
                self.performSegue(withIdentifier: "addLabel", sender: indexPath)
            }

        case 2:
            showTypeDetails = !showTypeDetails
            table.reloadData()

        default:
            tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if UIAccessibility.isVoiceOverRunning { // weird hack for word mode
            let left = -scrollView.adjustedContentInset.left
            if scrollView.contentOffset.x < left {
                let top = -scrollView.adjustedContentInset.top
                scrollView.contentOffset = CGPoint(x: left, y: top)
            }
        }
    }

    func addLabelController(_: AddLabelController, didEnterLabel: String?) {
        guard let indexPath = table.indexPathForSelectedRow else { return }
        table.deselectRow(at: indexPath, animated: true)

        guard let didEnterLabel, !didEnterLabel.isEmpty else { return }

        if indexPath.row < item.labels.count {
            item.labels[indexPath.row] = didEnterLabel
            table.reloadRows(at: [indexPath], with: .automatic)
        } else {
            item.labels.append(didEnterLabel)
            table.insertRows(at: [indexPath], with: .automatic)
        }
        makeIndexAndSaveItem()
    }

    func adaptivePresentationStyle(for _: UIPresentationController, traitCollection _: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }

    private func archiveWebComponent(cell: DetailCell, url: URL) {
        let a = UIAlertController(title: "Download", message: "Please choose what you would like to download from this URL.", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Archive Target", style: .default) { [weak self] _ in
            Task { [weak self] in
                await self?.proceedToArchiveWebComponent(cell: cell, url: url)
            }
        })
        a.addAction(UIAlertAction(title: "Image Thumbnail", style: .default) { [weak self] _ in
            Task { [weak self] in
                await self?.proceedToFetchLinkThumbnail(cell: cell, url: url)
            }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let p = a.popoverPresentationController {
            p.sourceView = cell.archiveButton
            p.sourceRect = cell.archiveButton.bounds
        }
        present(a, animated: true)
    }

    @MainActor
    private func proceedToFetchLinkThumbnail(cell: DetailCell, url: URL) async {
        cell.animateArchive(true)
        defer {
            cell.animateArchive(false)
        }
        do {
            let res = try await WebArchiver.shared.fetchWebPreview(for: url)
            if let image = res.image, let data = image.jpegData(compressionQuality: 1) {
                let newTypeItem = Component(typeIdentifier: UTType.jpeg.identifier, parentUuid: item.uuid, data: data, order: item.components.count)
                item.components.append(newTypeItem)
                handleNewTypeItem()
            } else {
                await genericAlert(title: "Image Download Failed", message: "There seems to be invalid image data.")
            }
        } catch {
            await genericAlert(title: "Image Download Failed", message: "The image could not be downloaded.")
        }
    }

    private func handleNewTypeItem() {
        item.needsReIngest = true
        makeIndexAndSaveItem()
        updateUI()
        if let newCell = table.cellForRow(at: IndexPath(row: 0, section: table.numberOfSections - 1)) {
            UIAccessibility.post(notification: .layoutChanged, argument: newCell)
        }
    }

    @MainActor
    private func proceedToArchiveWebComponent(cell: DetailCell, url: URL) async {
        cell.animateArchive(true)
        defer {
            cell.animateArchive(false)
        }

        do {
            let (data, typeIdentifier) = try await WebArchiver.shared.archiveFromUrl(url)
            let newTypeItem = Component(typeIdentifier: typeIdentifier, parentUuid: item.uuid, data: data, order: item.components.count)
            item.components.append(newTypeItem)
            handleNewTypeItem()
        } catch {
            await genericAlert(title: "Archiving Failed", message: error.finalDescription)
        }
    }

    private func refreshComponent(_ component: Component) {
        if let indexOfComponent = item.components.firstIndex(of: component) {
            let totalRows = tableView(table, numberOfRowsInSection: 2)
            if indexOfComponent >= totalRows { return }
            let ip = IndexPath(row: indexOfComponent, section: 2)
            table.reloadRows(at: [ip], with: .none)
        }
    }

    func textEditControllerMadeChanges(_ textEditController: TextEditController) {
        guard let component = textEditController.typeEntry else { return }
        refreshComponent(component)
    }
}
