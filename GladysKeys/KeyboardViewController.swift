import GladysCommon
import UIKit

private var latestOffset = CGPoint.zero
private var selectedLabel: String?

final class SimpleLabelToggleCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!

    override func setSelected(_ selected: Bool, animated _: Bool) {
        accessoryType = selected ? .checkmark : .none
        labelName.textColor = selected ? .label : .g_colorComponentLabel
    }
}

final class SimpleLabelPicker: UIViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet private var table: UITableView!
    @IBOutlet private var emptyLabel: UILabel!

    var changeCallback: (() -> Void)?

    let labels: [String] = {
        DropStore.visibleDrops
            .reduce(Set<String>()) { $0.union($1.labels) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        (view as? UIInputView)?.allowsSelfSizing = true

        var count = 1
        if let selected = selectedLabel {
            for toggle in labels {
                if toggle == selected {
                    table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
                }
                count += 1
            }
        } else {
            table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
        }

        if labels.isEmpty {
            table.isHidden = true
        } else {
            emptyLabel.isHidden = true
        }

        table.tableFooterView = UIView()
    }

    private var firstAppearance = true
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if firstAppearance {
            if let f = selectedLabel, !f.isEmpty, let index = labels.firstIndex(of: f) {
                table.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: false)
            }
            firstAppearance = false
        }
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        labels.count + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SimpleLabelToggleCell") as! SimpleLabelToggleCell
        if indexPath.row == 0 {
            cell.labelName.text = "Show All Items"
        } else {
            cell.labelName.text = labels[indexPath.row - 1]
        }
        return cell
    }

    func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let selected = selectedLabel {
            if indexPath.row > 0 {
                cell.setSelected(labels[indexPath.row - 1] == selected, animated: false)
            } else {
                cell.setSelected(false, animated: false)
            }
        } else {
            cell.setSelected(indexPath.row == 0, animated: false)
        }
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            selectedLabel = nil
        } else {
            selectedLabel = labels[indexPath.row - 1]
        }
        table.reloadData()
        changeCallback?()
        dismiss(animated: false)
    }
}

extension UIInputView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool {
        true
    }
}

final class KeyboardViewController: UIInputViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDragDelegate, UIPopoverPresentationControllerDelegate {
    @IBOutlet private var emptyLabel: UILabel!
    @IBOutlet private var itemsView: UICollectionView!
    @IBOutlet private var nextKeyboardButton: UIButton!
    @IBOutlet private var dismissButton: UIButton!
    @IBOutlet private var spaceButton: UIButton!
    @IBOutlet private var backspaceButton: UIButton!
    @IBOutlet private var enterButton: UIButton!
    @IBOutlet private var height: NSLayoutConstraint!
    @IBOutlet private var labelsButton: UIButton!
    @IBOutlet private var settingsButton: UIButton!
    @IBOutlet private var emptyStack: UIStackView!

    @IBOutlet private var topDivider: UIView!
    @IBOutlet private var topDividerHeight: NSLayoutConstraint!
    @IBOutlet private var bottomDividerHeight: NSLayoutConstraint!

    private var filteredDrops = ContiguousArray<ArchivedItem>()

    private func itemsPerRow(for size: CGSize) -> Int {
        if size.width <= 414 {
            3
        } else if size.width <= 768 {
            5
        } else {
            6
        }
    }

    private func updateItemSize(for size: CGSize) {
        guard size.width > 0 else { return }
        guard let layout = itemsView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let columnCount = CGFloat(itemsPerRow(for: size))

        let extras = layout.minimumInteritemSpacing * (columnCount - 1) + layout.sectionInset.left + layout.sectionInset.right
        let side = ((size.width - extras) / columnCount).rounded(.down)

        layout.itemSize = CGSize(width: side, height: side)
        layout.invalidateLayout()
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        filteredDrops.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "KeyboardCell", for: indexPath) as! KeyboardCell
        cell.dropItem = filteredDrops[indexPath.item]
        return cell
    }

    @IBAction private func closeTapped(_: UIButton) {
        dismissKeyboard()
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        UIDevice.current.playInputClick()
        let drop = filteredDrops[indexPath.item]
        let (text, url) = drop.textForMessage
        textDocumentProxy.insertText(url?.absoluteString ?? text)
        updateReturn()
    }

    func collectionView(_: UICollectionView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let drop = filteredDrops[indexPath.item]
        return [drop.dragItem]
    }

    func collectionView(_: UICollectionView, dragSessionWillBegin _: UIDragSession) {
        dragCompletionGroup.enter()
    }

    func collectionView(_: UICollectionView, dragSessionDidEnd _: UIDragSession) {
        dragCompletionGroup.leave()
    }

    func collectionView(_: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        if let cell = itemsView.cellForItem(at: indexPath) as? KeyboardCell, let b = cell.backgroundView {
            let corner = b.layer.cornerRadius
            let params = UIDragPreviewParameters()
            params.visiblePath = UIBezierPath(roundedRect: b.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: corner, height: corner))
            return params
        } else {
            return nil
        }
    }

    @IBAction private func returnSelected(_: UIButton) {
        UIDevice.current.playInputClick()
        textDocumentProxy.insertText("\n")
        updateReturn()
    }

    @IBAction private func spaceSelected(_: UIButton) {
        UIDevice.current.playInputClick()
        textDocumentProxy.insertText(" ")
        updateReturn()
    }

    private weak var backspaceTimer: Timer?

    @IBAction private func deleteStarted(_: UIButton) {
        UIDevice.current.playInputClick()
        textDocumentProxy.deleteBackward()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            self?.startRapidBackspace()
        }
    }

    private func startRapidBackspace() {
        textDocumentProxy.deleteBackward()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.textDocumentProxy.deleteBackward()
        }
    }

    @IBAction private func deleteEnded(_: UIButton) {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
    }

    private func updateFilteredItems() {
        if let f = selectedLabel, !f.isEmpty {
            filteredDrops = DropStore.visibleDrops.filter { $0.labels.contains(f) }
        } else {
            filteredDrops = DropStore.visibleDrops
        }
    }

    private func externalDataUpdated() {
        let items = ContiguousArray(LiteModel.allItems())
        DropStore.boot(with: items)
        updateFilteredItems()
        if filteredDrops.isEmpty {
            emptyStack.isHidden = false
            settingsButton.isHidden = true
        } else {
            emptyStack.isHidden = true
        }
        updateItemSize(for: view.bounds.size)
        itemsView.reloadData()
    }

    deinit {
        log("Keyboard extension dismissed")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if hasFullAccess {
            emptyLabel.text = "The items in your collection will appear here."
        } else {
            emptyLabel.text = "This keyboard requires perimssion to access your Gladys collection.\n\nPlease enable it from Gladys > Keyboards > Allow Full Access"
            emptyStack.isHidden = false
            settingsButton.isHidden = false
            return
        }

        externalDataUpdated()
        view.layoutIfNeeded()
        itemsView.contentOffset = latestOffset
        updateReturn()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateReturn()
    }

    private func updateReturn() {
        switch textDocumentProxy.returnKeyType {
        case .continue:
            enterButton.setTitle("Continue", for: .normal)
            enterButton.setImage(nil, for: .normal)
        case .done:
            enterButton.setTitle("Done", for: .normal)
            enterButton.setImage(nil, for: .normal)
        case .go:
            enterButton.setTitle("Go", for: .normal)
            enterButton.setImage(nil, for: .normal)
        case .next:
            enterButton.setTitle("Next", for: .normal)
            enterButton.setImage(nil, for: .normal)
        case .search:
            enterButton.setTitle("Search", for: .normal)
            enterButton.setImage(nil, for: .normal)
        default:
            break
        }

        let enabled: Bool = if textDocumentProxy.enablesReturnKeyAutomatically == true {
            textDocumentProxy.hasText
        } else {
            true
        }
        enterButton.isEnabled = enabled
        enterButton.alpha = enabled ? 1 : 0.4
    }

    private let dragCompletionGroup = DispatchGroup()

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dragCompletionGroup.notify(queue: .main) {
            latestOffset = self.itemsView.contentOffset
            DropStore.reset()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        updateItemSize(for: size)
        coordinator.animate { _ in
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dismissButton.isHidden = UIDevice.current.userInterfaceIdiom != .pad
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        itemsView.dragDelegate = self
        itemsView.dragInteractionEnabled = UIDevice.current.userInterfaceIdiom == .pad

        topDivider.isHidden = UIDevice.current.userInterfaceIdiom == .phone

        let pixelHeight: CGFloat = 1 / UIScreen.main.scale
        topDividerHeight.constant = pixelHeight
        bottomDividerHeight.constant = pixelHeight

        height.constant = min(400, UIScreen.main.bounds.height * 0.5)

        let config: UIImage.SymbolConfiguration
        if traitCollection.containsTraits(in: UITraitCollection(horizontalSizeClass: .regular)) {
            config = UIImage.SymbolConfiguration(pointSize: 23, weight: .light, scale: .default)
        } else {
            config = UIImage.SymbolConfiguration(pointSize: 19, weight: .light, scale: .default)
        }

        for b in [labelsButton, dismissButton, spaceButton, backspaceButton, enterButton, nextKeyboardButton] {
            b?.layer.masksToBounds = true
            b?.layer.cornerRadius = 5
            b?.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        }

        dismissButton.backgroundColor = UIColor.g_colorKeyboardGray

        spaceButton.backgroundColor = UIColor.g_colorKeyboardBright

        backspaceButton.backgroundColor = UIColor.g_colorKeyboardGray

        labelsButton.backgroundColor = UIColor.g_colorKeyboardGray

        nextKeyboardButton.backgroundColor = UIColor.g_colorKeyboardGray
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturn()
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        guard let d = segue.destination as? SimpleLabelPicker else {
            return
        }
        d.popoverPresentationController?.delegate = self
        d.changeCallback = { [weak self] in
            self?.externalDataUpdated()
        }
    }

    @IBAction private func settingsSelected(_: UIButton) {
        let url = URL(string: UIApplication.openSettingsURLString)!

        let selector = sel_registerName("openURL:")
        var responder = self as UIResponder?
        while let r = responder, !r.responds(to: selector) {
            responder = r.next
        }
        _ = responder?.perform(selector, with: url)
    }

    func adaptivePresentationStyle(for _: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func collectionView(_: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        let item = filteredDrops[indexPath.item]

        return UIContextMenuConfiguration(identifier: item.uuid.uuidString as NSString, previewProvider: nil) { _ in
            let copyAction = UIAction(title: "Copy") { _ in
                item.copyToPasteboard()
            }
            copyAction.image = UIImage(systemName: "doc.on.doc")
            let typeAction = UIAction(title: "Type") { [weak self] _ in
                let (text, url) = item.textForMessage
                UIDevice.current.playInputClick()
                self?.textDocumentProxy.insertText(url?.absoluteString ?? text)
                self?.updateReturn()
            }
            typeAction.image = UIImage(systemName: "keyboard")
            let (text, url) = item.textForMessage
            let title = url?.absoluteString ?? text
            return UIMenu(title: title, image: nil, identifier: nil, options: [], children: [typeAction, copyAction])
        }
    }

    func collectionView(_: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        previewForContextMenu(of: configuration)
    }

    func collectionView(_: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        previewForContextMenu(of: configuration)
    }

    private func previewForContextMenu(of configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        if
            let uuid = configuration.identifier as? String,
            let item = DropStore.item(uuid: uuid),
            let index = filteredDrops.firstIndex(of: item),
            let cell = itemsView.cellForItem(at: IndexPath(item: index, section: 0)) as? KeyboardCell {
            return cell.targetedPreviewItem
        }
        return nil
    }
}
