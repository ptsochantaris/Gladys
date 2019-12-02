
import UIKit
import CloudKit
import MobileCoreServices

final class DetailController: GladysViewController,
	UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate,
	UIPopoverPresentationControllerDelegate, AddLabelControllerDelegate, TextEditControllerDelegate,
	UICloudSharingControllerDelegate {

	var item: ArchivedDropItem!

	private var showTypeDetails = false

	@IBOutlet private weak var table: UITableView!
	@IBOutlet private weak var openButton: UIBarButtonItem!
	@IBOutlet private weak var dateItem: UIBarButtonItem!
	@IBOutlet private weak var dateLabel: UILabel!
	@IBOutlet private weak var dateLabelHolder: UIView!
	@IBOutlet private weak var deleteButton: UIBarButtonItem!
	@IBOutlet private weak var copyButton: UIBarButtonItem!
	@IBOutlet private weak var shareButton: UIBarButtonItem!
	@IBOutlet private weak var lockButton: UIBarButtonItem!
	@IBOutlet private weak var invitesButton: UIBarButtonItem?
	@IBOutlet private weak var siriButton: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()

		doneButtonLocation = .right
        windowButtonLocation = .right

		table.estimatedRowHeight = 120
        table.rowHeight = UITableView.automaticDimension
		table.dragInteractionEnabled = true
		table.dragDelegate = self
		table.dropDelegate = self
		table.dragInteractionEnabled = true

		deleteButton.accessibilityLabel = "Delete item"
		copyButton.accessibilityLabel = "Copy item to clipboard"
		shareButton.accessibilityLabel = "Share"
		siriButton.accessibilityLabel = "Siri shortcuts"
		updateLockButton()
		updateInviteButton()

		openButton.isEnabled = item.canOpen

		dateLabel.text = item.addedString
		dateItem.customView = dateLabelHolder

		if !CloudManager.syncSwitchedOn {
			navigationItem.rightBarButtonItems = navigationItem.rightBarButtonItems?.filter { $0 != invitesButton }
		}
        		
		userActivity = NSUserActivity(activityType: kGladysDetailViewingActivity)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(keyboardHiding(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
		n.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        n.addObserver(self, selector: #selector(dataUpdate(_:)), name: .ModelDataUpdated, object: nil)
		n.addObserver(self, selector: #selector(updateUI), name: .ItemModified, object: item)
        n.addObserver(self, selector: #selector(updateUI), name: .IngestComplete, object: item)
	}

	private func updateLockButton() {
		if item.isLocked {
			lockButton.accessibilityLabel = "Remove Lock"
			lockButton.image = UIImage(systemName: "lock.fill")
		} else {
			lockButton.accessibilityLabel = "Lock Item"
			lockButton.image = UIImage(systemName: "lock.open")
		}
		lockButton.isEnabled = !item.isImportedShare
	}
    
    @objc private func dataUpdate(_ notification: Notification) {
        if let removedUUIDSs = (notification.object as? [AnyHashable: Any])?["removed"] as? [UUID], let uuid = item?.uuid, removedUUIDSs.contains(uuid) {
            done()
        } else {
            updateUI()
        }
    }

	private func updateInviteButton() {
		if let invitesButton = invitesButton {
			invitesButton.isEnabled = CloudManager.syncSwitchedOn

			switch item.shareMode {
			case .none:
				invitesButton.image = UIImage(systemName: "person.crop.circle.badge.plus")
				invitesButton.accessibilityLabel = "Share With Others"
                invitesButton.tintColor = UIColor(named: "colorTint")
			case .elsewhereReadOnly, .elsewhereReadWrite:
				invitesButton.image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")
				invitesButton.accessibilityLabel = "Imported Share Options"
                invitesButton.tintColor = UIColor(named: "colorGray")
			case .sharing:
				invitesButton.image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")
				invitesButton.accessibilityLabel = "Exported Share Options"
				invitesButton.tintColor = UIColor(named: "colorTint")
			}
		}

		let readWrite = item.shareMode != .elsewhereReadOnly
		table.allowsSelection = readWrite
		table.dragInteractionEnabled = readWrite

		title = readWrite ? nil : "Read Only"

		var titleView: UILabel?
		if let title = title {
			titleView = navigationItem.titleView as? UILabel
			if titleView == nil {
				titleView = UILabel()
				titleView!.font = UIFont.preferredFont(forTextStyle: .caption1)
				titleView!.textColor = UIColor(named: "colorTint")
			}
			titleView!.text = title
		}
		navigationItem.titleView = titleView
	}

	@IBAction private func inviteButtonSelected(_ sender: UIBarButtonItem) {
		if item.shareMode == .none {
			addInvites(sender)
		} else if item.isPrivateShareWithOnlyOwner {
			shareOptionsPrivate(sender)
		} else if item.isShareWithOnlyOwner {
			shareOptionsPublic(sender)
		} else {
			editInvites(sender)
		}
	}

	@IBAction private func lockButtonSelected(_ sender: UIBarButtonItem) {
		if let p = presentedViewController {
			p.dismiss(animated: false, completion: nil)
		}
		if item.isLocked {
			item.unlock(from: self, label: "Remove Lock", action: "Remove") { [weak self] success in
				if success, let s = self {
					s.passwordUpdate(nil, hint: nil)
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						genericAlert(title: "Lock Removed", message: nil, buttonTitle: nil)
					}
				}
			}
		} else {
			item.lock(from: self) { [weak self] passwordData, passwordHint in
				if let d = passwordData, let s = self {
					s.passwordUpdate(d, hint: passwordHint)
				}
			}
		}
	}

	private func passwordUpdate(_ newPassword: Data?, hint: String?) {
		item.lockPassword = newPassword
		if let hint = hint, !hint.isEmpty {
			item.lockHint = hint
		} else {
			item.lockHint = nil
		}
		updateLockButton()
		updateInviteButton()
		makeIndexAndSaveItem()
		item.postModified()
		if item.needsUnlock {
			done()
		}
	}

	override func updateUserActivityState(_ activity: NSUserActivity) {
		super.updateUserActivityState(activity)
		if let item = item { // check for very weird corner case where item may be nil
			ArchivedDropItem.updateUserActivity(activity, from: item, child: nil, titled: "Info of")
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
		if item == nil {
			done()
		} else {
			table.reloadData()
			updateLockButton()
			updateInviteButton()
			sizeWindow()
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
			NotificationCenter.default.post(name: .DetailViewClosing, object: nil, userInfo: nil)
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		//log("laid-out for \(view.bounds.size)")
        sizeWindow()
	}

	private var initialWidth: CGFloat = 0

	private func sizeWindow() {
		let preferredSize: CGSize
		if initialWidth > 0 {
			//log("adapt to table height")
			preferredSize = CGSize(width: initialWidth, height: table.contentSize.height)
		} else {
			//log("table layout")
			table.layoutIfNeeded()
			preferredSize = table.contentSize
			initialWidth = preferredSize.width
		}
		//log("set preferred size to \(preferredSize)")
		preferredContentSize = preferredSize
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        if !firstAppearance {
            preferredContentSize = .zero
            sizeWindow()
        }
	}

	override var keyCommands: [UIKeyCommand]? {
		var a = super.keyCommands ?? []
        let c = UIKeyCommand.makeCommand(input: "c", modifierFlags: .command, action: #selector(copyPressed), title: "Copy Item to Clipboard")
        a.append(c)
		return a
	}

	@objc private func copyPressed() {
		copySelected(copyButton)
	}

	@IBAction private func shareSelected(_ sender: UIBarButtonItem) {
		if let p = presentedViewController {
			p.dismiss(animated: false, completion: nil)
		}
		let a = UIActivityViewController(activityItems: [item.sharingActivitySource], applicationActivities: nil)
		present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
	}

	@IBAction private func copySelected(_ sender: UIBarButtonItem) {
		item.copyToPasteboard()
		genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
	}

	@IBAction private func openSelected(_ sender: UIBarButtonItem) {
		item.tryOpen(in: navigationController!) { shouldClose in
			if shouldClose {
				self.done()
			}
		}
	}

	@IBAction private func deleteSelected(_ sender: UIBarButtonItem) {
		if let p = presentedViewController {
			p.dismiss(animated: false, completion: nil)
		}
		var title, message: String?
		if item.shareMode == .sharing {
			title = "You are sharing this item"
			message = "Deleting it will remove it from others' collections too."
		}
		let a = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Delete Item", style: .destructive) { action in
			self.done()
			if let item = self.item {
				DispatchQueue.main.async {
                    Model.delete(items: [item])
				}
			}
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 2 {
			return item.labels.count + 1
		}
		if section == 3 {
			return item.typeItems.count
		}
		return 1
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return (item.typeItems.count > 0 ? 1 : 0) + 3
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section < 2 {
			return nil
		} else if section == 2 {
			return "Labels"
		} else {
			return "Components"
		}
	}

	private func cellNeedsResize(caretRect: CGRect?, section: Int, heightChange: Bool) {
		if heightChange {
			UIView.performWithoutAnimation {
				table.beginUpdates()
				table.endUpdates()
			}
			DispatchQueue.main.async {
				self.sizeWindow()
			}
		}
		if let caretRect = caretRect {
			table.scrollRectToVisible(caretRect, animated: false)
		} else {
			table.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
		}
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		if indexPath.section == 0 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath) as! HeaderCell
			cell.item = item
			cell.isUserInteractionEnabled = item.shareMode != .elsewhereReadOnly
			cell.resizeCallback = { [weak self] caretRect, heightChange in
				self?.cellNeedsResize(caretRect: caretRect, section: indexPath.section, heightChange: heightChange)
			}
			return cell

		} else if indexPath.section == 1 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as! NoteCell
			cell.item = item
			cell.isUserInteractionEnabled = item.shareMode != .elsewhereReadOnly
			cell.resizeCallback = { [weak self] caretRect, heightChange in
				self?.cellNeedsResize(caretRect: caretRect, section: indexPath.section, heightChange: heightChange)
			}
			return cell

		} else if indexPath.section == 2 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath) as! LabelCell
			if indexPath.row < item.labels.count {
				cell.label = item.labels[indexPath.row]
			} else {
				cell.label = nil
			}
			return cell

		} else {

			let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath) as! DetailCell
			let typeEntry = item.typeItems[indexPath.row]
            if cell.configure(with: typeEntry, showTypeDetails: showTypeDetails, darkMode: darkMode) {
                setCallbacks(for: cell, for: typeEntry)
            }
			return cell
		}
	}
    
    private lazy var darkMode = {
        view.traitCollection.containsTraits(in: UITraitCollection(userInterfaceStyle: .dark))
    }()

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        darkMode = newCollection.containsTraits(in: UITraitCollection(userInterfaceStyle: .dark))
    }
    
	private func checkInspection(for component: ArchivedDropItemType, in cell: DetailCell) {
		if component.bytes?.isPlist == true {
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

	private func setCallbacks(for cell: DetailCell, for typeEntry: ArchivedDropItemType) {

		cell.inspectionCallback = { [weak cell, weak self] in
			if let s = self, let c = cell {
				s.checkInspection(for: typeEntry, in: c)
			}
		}

		let readWrite = item.shareMode != .elsewhereReadOnly

		let itemURL = typeEntry.encodedUrl
		if readWrite, let i = itemURL, let s = i.scheme, s.hasPrefix("http") {
			cell.archiveCallback = { [weak self, weak cell] in
				if let s = self, let c = cell {
					s.archiveWebComponent(cell: c, url: i as URL)
				}
			}
		} else {
			cell.archiveCallback = nil
		}

		if readWrite, itemURL != nil {
			cell.editCallback = { [weak self] in
				self?.editURL(typeEntry, existingEdit: nil)
			}
		} else if readWrite, typeEntry.isText {
			cell.editCallback = { [weak self] in
				self?.performSegue(withIdentifier: "textEdit", sender: typeEntry)
			}
		} else {
			cell.editCallback = nil
		}

		if typeEntry.canPreview {
			cell.viewCallback = { [weak self, weak cell] in
				guard let s = self, let c = cell else { return }
                                
                let scene = s.view.window?.windowScene
                guard let q = typeEntry.quickLook(in: scene) else { return }
                if s.phoneMode || !PersistedOptions.fullScreenPreviews {
                    let n = PreviewHostingInternalController(nibName: nil, bundle: nil)
                    n.qlController = q
					s.navigationController?.pushViewController(n, animated: true)
                    
				} else if let presenter = s.view.window?.alertPresenter {
                    let n = PreviewHostingViewController(rootViewController: q)
                    n.sourceItemView = c
                    presenter.present(n, animated: true)
				}
			}
		} else {
			cell.viewCallback = nil
		}
	}
    
	private func editURL(_ typeItem: ArchivedDropItemType, existingEdit: String?) {
		getInput(from: self, title: "Edit URL", action: "Change", previousValue: existingEdit ?? typeItem.encodedUrl?.absoluteString) { [weak self] newValue in
			guard let s = self else { return }
			if let newValue = newValue, let newURL = NSURL(string: newValue), let scheme = newURL.scheme, !scheme.isEmpty {
				typeItem.replaceURL(newURL)
				s.item.needsReIngest = true
				s.makeIndexAndSaveItem()
				s.refreshComponent(typeItem)
			} else if let newValue = newValue {
				genericAlert(title: "This is not a valid URL", message: newValue) {
					s.editURL(typeItem, existingEdit: newValue)
				}
			}
		}
	}

	func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		if indexPath.section != 3 { return UISwipeActionsConfiguration(actions: []) }
		let copy = UIContextualAction(style: .normal, title: "Copy") { [weak self] action, view, handler in
			self?.copyRowSelected(at: indexPath)
			handler(true)
		}
		return UISwipeActionsConfiguration(actions: [copy])
	}

	func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		if indexPath.section < 2 { return UISwipeActionsConfiguration(actions: []) }
		if indexPath.section == 2 && indexPath.row == item.labels.count { return UISwipeActionsConfiguration(actions: []) }
		if item.shareMode == .elsewhereReadOnly { return UISwipeActionsConfiguration(actions: []) }
		let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] action, view, handler in
			let ok = self?.deleteRowSelected(at: indexPath) ?? false
			handler(ok)
		}
		return UISwipeActionsConfiguration(actions: [delete])
	}

	private func deleteRowSelected(at indexPath: IndexPath) -> Bool {
		if CloudManager.syncing || item.needsReIngest || item.isTransferring {
			genericAlert(title: "Syncing", message: "Please try again in a moment.", buttonTitle: nil)
			return false
		}
		table.performBatchUpdates({
			if indexPath.section == 2 {
				self.removeLabel(at: indexPath)
			} else {
				self.removeTypeItem(at: indexPath)
			}
		}, completion: { _ in
			self.sizeWindow()
			UIAccessibility.post(notification: .layoutChanged, argument: self.table)
		})
		return true
	}

	private func copyRowSelected(at indexPath: IndexPath) {
		let typeItem = item.typeItems[indexPath.row]
		typeItem.copyToPasteboard()
		genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
	}

	private func removeLabel(at indexPath: IndexPath) {
		item.labels.remove(at: indexPath.row)
		table.deleteRows(at: [indexPath], with: .automatic)
		makeIndexAndSaveItem()
		item.postModified()
	}

	private func removeTypeItem(at indexPath: IndexPath) {
		let typeItem = item.typeItems[indexPath.row]
		item.typeItems.remove(at: indexPath.row)
		typeItem.deleteFromStorage()
		if item.typeItems.count == 0 {
			table.deleteSections(IndexSet(integer: 3), with: .automatic)
		} else {
			table.deleteRows(at: [indexPath], with: .automatic)
		}
		item.renumberTypeItems()
		item.needsReIngest = true
		makeIndexAndSaveItem()
	}

	override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
		if identifier == "toSiriShortcuts" {
			return view.endEditing(false)
		}
		return true
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "textEdit",
			let typeEntry = sender as? ArchivedDropItemType,
			let e = segue.destination as? TextEditController {
			e.item = item
			e.typeEntry = typeEntry
			e.delegate = self

		} else if segue.identifier == "hexEdit",
			let typeEntry = sender as? ArchivedDropItemType,
			let e = segue.destination as? HexEdit {
			
			e.bytes = typeEntry.bytes ?? Data()
			
			let f = ByteCountFormatter()
			let size = f.string(fromByteCount: Int64(e.bytes.count))
			e.title = typeEntry.typeDescription + " (\(size))"

		} else if segue.identifier == "plistEdit",
			let typeEntry = sender as? ArchivedDropItemType,
			let e = segue.destination as? PlistEditor,
			let b = typeEntry.bytes,
			let propertyList = try? PropertyListSerialization.propertyList(from: b, options: [], format: nil) {

			e.title = typeEntry.trimmedName
			e.propertyList = propertyList

		} else if segue.identifier == "toSiriShortcuts" {
            if let d = segue.destination as? SiriShortcutsViewController {
                d.detailActivity = userActivity
                d.sourceItem = item
                if let p = d.popoverPresentationController {
                    p.delegate = self
                }
            }

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
            d.modelFilter = view.associatedFilter
			p.delegate = self
			if indexPath.row < item.labels.count {
				d.title = "Edit Label"
				d.label = item.labels[indexPath.row]
			} else {
				d.title = "Add Label"
			}
		}
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		if section == 0 {
			return 10
		} else if section == 1 {
			return CGFloat.leastNonzeroMagnitude
		} else {
			return 33
		}
	}

	func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		if section == 3 {
			return 6
		} else if section < 2 {
			return CGFloat.leastNonzeroMagnitude
		} else {
			return 0
		}
	}

	func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		if indexPath.section < 2 {
			return []
		} else if indexPath.section == 2 {
			if let i = item.dragItem(forLabelIndex: indexPath.row) {
				session.localContext = "label"
				return [i]
			} else {
				return []
			}
		} else {
			let typeItem = item.typeItems[indexPath.row]
			session.localContext = "typeItem"
			return [typeItem.dragItem]
		}
	}

	func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
		if let d = destinationIndexPath, let s = session.localDragSession, item.shareMode != .elsewhereReadOnly && !item.shouldDisplayLoading {
			if d.section == 2, d.row < item.labels.count, s.canLoadObjects(ofClass: String.self) {
				if let simpleString = s.items.first?.localObject as? String, item.labels.contains(simpleString) {
					return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
				}
				return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
			}
			if d.section == 3, let candidate = s.items.first?.localObject as? ArchivedDropItemType {
				let operationType: UIDropOperation = item.typeItems.contains(candidate) ? .move : .copy
				return UITableViewDropProposal(operation: operationType, intent: .insertAtDestinationIndexPath)
			}
		}
		return UITableViewDropProposal(operation: .cancel)
	}

	func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) {
		if session.localContext as? String == "typeItem" {
			componentDropActiveFromDetailView = nil
		}
	}

	func tableView(_ tableView: UITableView, dropSessionDidExit session: UIDropSession) {
		if let session = session.localDragSession {
			if session.localContext as? String == "typeItem" {
				componentDropActiveFromDetailView = self
			}
            if !isAccessoryWindow {
                done()
            }
		}
	}

	func tableView(_ tableView: UITableView, dropSessionDidEnter session: UIDropSession) {
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

				if destinationIndexPath.section == 2 {
					let existingLabel = localObject as? String
					if previousIndex.section == 2 {
						item.labels.remove(at: previousIndex.row)
						item.labels.insert(existingLabel ?? "...", at: destinationIndexPath.row)
						item.postModified()
						tableView.performBatchUpdates({
							tableView.reloadData()
						})
					} else {
						item.labels.insert(existingLabel ?? "...", at: destinationIndexPath.row)
						item.postModified()
						tableView.performBatchUpdates({
							tableView.insertRows(at: [destinationIndexPath], with: .automatic)
						})
					}

					if existingLabel == nil {
						_ = dragItem.itemProvider.loadObject(ofClass: String.self) { newLabel, error in
							if let newLabel = newLabel {
								DispatchQueue.main.async {
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

				} else if destinationIndexPath.section == 3, previousIndex.section == 3 {

					// moving internal type item
					let destinationIndex = destinationIndexPath.row
					let sourceItem = item.typeItems[previousIndex.row]
					item.typeItems.remove(at: previousIndex.row)
					item.typeItems.insert(sourceItem, at: destinationIndex)
					item.renumberTypeItems()
					table.performBatchUpdates({
						table.moveRow(at: previousIndex, to: destinationIndexPath)
					}, completion: { _ in
						self.handleNewTypeItem()
					})
				}

			} else if let candidate = dragItem.localObject as? ArchivedDropItemType {
				if destinationIndexPath.section == 2 {
					// dropping external type item into labels
					if let text = candidate.displayTitle {
						item.labels.insert(text, at: destinationIndexPath.row)
						item.postModified()
						tableView.performBatchUpdates({
							tableView.insertRows(at: [destinationIndexPath], with: .automatic)
						}, completion: { _ in
							self.makeIndexAndSaveItem()
						})
					}

				} else if destinationIndexPath.section == 3 {
					// dropping external type item into type items
					let itemCopy = ArchivedDropItemType(from: candidate, newParent: item)
					item.typeItems.insert(itemCopy, at: destinationIndexPath.item)
					item.renumberTypeItems()
					tableView.performBatchUpdates({
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
		let cell = table.cellForRow(at: indexPath)
		if let cell = cell as? DetailCell {
			let path = UIBezierPath(roundedRect: cell.borderView.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
			let p = UIDragPreviewParameters()
			p.visiblePath = path
			return p
		} else if let cell = cell as? LabelCell {
			let path = UIBezierPath(roundedRect: cell.labelHolder.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
			let p = UIDragPreviewParameters()
			p.visiblePath = path
			return p
		} else {
			return nil
		}
	}

	func tableView(_ tableView: UITableView, dragPreviewParametersForRowAt indexPath: IndexPath) -> UIDragPreviewParameters? {
		return dragParameters(for: indexPath)
	}

	func tableView(_ tableView: UITableView, dropPreviewParametersForRowAt indexPath: IndexPath) -> UIDragPreviewParameters? {
		return dragParameters(for: indexPath)
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		view.endEditing(false)

		if indexPath.section == 3 {
			showTypeDetails = !showTypeDetails
			table.reloadData()
		}

		guard indexPath.section == 2 else {
			tableView.deselectRow(at: indexPath, animated: false)
			return
		}

		DispatchQueue.main.async {
			self.performSegue(withIdentifier: "addLabel", sender: indexPath)
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

	func addLabelController(_ addLabelController: AddLabelController, didEnterLabel: String?) {

		guard let indexPath = table.indexPathForSelectedRow else { return }
		table.deselectRow(at: indexPath, animated: true)

		guard let didEnterLabel = didEnterLabel, !didEnterLabel.isEmpty else { return }

		if indexPath.row < item.labels.count {
			item.labels[indexPath.row] = didEnterLabel
			table.reloadRows(at: [indexPath], with: .automatic)
		} else {
			item.labels.append(didEnterLabel)
			table.insertRows(at: [indexPath], with: .automatic)
		}
		makeIndexAndSaveItem()
		item.postModified()
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}

	private func archiveWebComponent(cell: DetailCell, url: URL) {
		let a = UIAlertController(title: "Download", message: "Please choose what you would like to download from this URL.", preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Archive Target", style: .default) { _ in
			self.proceedToArchiveWebComponent(cell: cell, url: url)
		})
		a.addAction(UIAlertAction(title: "Image Thumbnail", style: .default) { _ in
			self.proceedToFetchLinkThumbnail(cell: cell, url: url)
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		if let p = a.popoverPresentationController {
			p.sourceView = cell.archiveButton
			p.sourceRect = cell.archiveButton.bounds
		}
		present(a, animated: true)
	}

	private func proceedToFetchLinkThumbnail(cell: DetailCell, url: URL) {
		cell.animateArchive(true)
		WebArchiver.fetchWebPreview(for: url) { _, _, image, _ in
			if let image = image, let data = image.jpegData(compressionQuality: 1) {
				DispatchQueue.main.async {
					let newTypeItem = ArchivedDropItemType(typeIdentifier: kUTTypeJPEG as String, parentUuid: self.item.uuid, data: data, order: self.item.typeItems.count)
					self.item.typeItems.append(newTypeItem)
					self.handleNewTypeItem()
				}
			} else {
				DispatchQueue.main.async {
					genericAlert(title: "Image Download Failed", message: "The image could not be downloaded.")
				}
			}
			DispatchQueue.main.async {
				cell.animateArchive(false)
			}
		}
	}

	private func handleNewTypeItem() {
		item.needsReIngest = true
		makeIndexAndSaveItem()
		updateUI()
		item.postModified()
		item.reIngest()
		if let newCell = table.cellForRow(at: IndexPath(row: 0, section: table.numberOfSections-1)) {
			UIAccessibility.post(notification: .layoutChanged, argument: newCell)
		}
	}

	private func proceedToArchiveWebComponent(cell: DetailCell, url: URL) {
		cell.animateArchive(true)
		
		WebArchiver.archiveFromUrl(url) { data, typeIdentifier, error in
			if let error = error {
				DispatchQueue.main.async {
					genericAlert(title: "Archiving Failed", message: error.finalDescription)
				}
			} else if let data = data, let typeIdentifier = typeIdentifier {
				DispatchQueue.main.async {
					let newTypeItem = ArchivedDropItemType(typeIdentifier: typeIdentifier, parentUuid: self.item.uuid, data: data, order: self.item.typeItems.count)
					self.item.typeItems.append(newTypeItem)
					self.handleNewTypeItem()
				}
			}
			DispatchQueue.main.async {
				cell.animateArchive(false)
			}
		}
	}

	private func refreshComponent(_ component: ArchivedDropItemType) {
		if let indexOfComponent = item.typeItems.firstIndex(of: component) {
			let totalRows = tableView(table, numberOfRowsInSection: 3)
			if indexOfComponent >= totalRows { return }
			let ip = IndexPath(row: indexOfComponent, section: 3)
			table.reloadRows(at: [ip], with: .none)
		}
	}

	func textEditControllerMadeChanges(_ textEditController: TextEditController) {
		guard let component = textEditController.typeEntry else { return }
		refreshComponent(component)
	}

	//////////////////////////////// Sharing

	private func addInvites(_ sender: Any) {
		guard let barButtonItem = sender as? UIBarButtonItem, let rootRecord = item.cloudKitRecord else { return }

		let cloudSharingController = UICloudSharingController { [weak self] (controller, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) in
			guard let s = self else { return }
			CloudManager.share(item: s.item, rootRecord: rootRecord, completion: completion)
		}
		presentCloudController(cloudSharingController, from: barButtonItem)
	}

	private func editInvites(_ sender: Any) {
		guard let barButtonItem = sender as? UIBarButtonItem, let shareRecord = item.cloudKitShareRecord else { return }
		let cloudSharingController = UICloudSharingController(share: shareRecord, container: CloudManager.container)
		presentCloudController(cloudSharingController, from: barButtonItem)
	}

	private func presentCloudController(_ cloudSharingController: UICloudSharingController, from barButtonItem: UIBarButtonItem) {
		if let popover = cloudSharingController.popoverPresentationController {
			popover.barButtonItem = barButtonItem
		}
		cloudSharingController.delegate = self
		present(cloudSharingController, animated: true)
	}

	func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
		genericAlert(title: "Could not share this item", message: error.finalDescription)
	}

	func itemTitle(for csc: UICloudSharingController) -> String? {
		return item.trimmedSuggestedName
	}

	func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
		item.cloudKitShareRecord = csc.share
		item.postModified()
		updateInviteButton()
	}

	func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
		guard let i = item else { return }
		let wasImported = i.isImportedShare
		i.cloudKitShareRecord = nil
		updateInviteButton()
		if wasImported {
			DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { [weak self] in
				self?.done()
                Model.delete(items: [i])
			}
		} else {
			item.postModified()
			updateInviteButton()
		}
	}

	func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
		var data: Data?
		if let ip = item.imagePath {
			dataAccessQueue.sync {
				data = try? Data(contentsOf: ip)
			}
		}
		return data
	}

	private func shareOptionsPrivate(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "No Participants", message: "This item is shared privately, but has no participants yet. You can edit options to make it public, invite more people, or stop sharing it.", preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Options", style: .default) { [weak self] _ in
			self?.editInvites(sender)
		})
		a.addAction(UIAlertAction(title: "Stop Sharing", style: .destructive) { [weak self] _ in
			self?.deleteShare(sender)
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
		a.popoverPresentationController?.barButtonItem = sender
	}

	private func shareOptionsPublic(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "No Participants", message: "This item is shared publicly, but has no participants yet. You can edit options to make it private and invite people, or stop sharing it.", preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Make Private", style: .default) { [weak self] _ in
			self?.editInvites(sender)
		})
		a.addAction(UIAlertAction(title: "Stop Sharing", style: .destructive) { [weak self] _ in
			self?.deleteShare(sender)
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
		a.popoverPresentationController?.barButtonItem = sender
	}

	private func deleteShare(_ sender: UIBarButtonItem) {
		sender.isEnabled = false
		CloudManager.deleteShare(item) { _ in
			sender.isEnabled = true
		}
	}
}
