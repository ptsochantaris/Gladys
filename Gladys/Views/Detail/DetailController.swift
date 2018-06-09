
import UIKit
import CloudKit

final class DetailController: GladysViewController,
	UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate,
	UIPopoverPresentationControllerDelegate, AddLabelControllerDelegate, TextEditControllerDelegate,
	UICloudSharingControllerDelegate {

	var item: ArchivedDropItem!

	private var showTypeDetails = false

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var openButton: UIBarButtonItem!
	@IBOutlet weak var dateItem: UIBarButtonItem!
	@IBOutlet weak var dateLabel: UILabel!
	@IBOutlet weak var dateLabelHolder: UIView!
	@IBOutlet weak var deleteButton: UIBarButtonItem!
	@IBOutlet weak var copyButton: UIBarButtonItem!
	@IBOutlet weak var shareButton: UIBarButtonItem!
	@IBOutlet weak var lockButton: UIBarButtonItem!
	@IBOutlet weak var invitesButton: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		table.estimatedRowHeight = 120
        table.rowHeight = UITableViewAutomaticDimension
		table.dragInteractionEnabled = true
		table.dragDelegate = self
		table.dropDelegate = self
		table.dragInteractionEnabled = true

		deleteButton.accessibilityLabel = "Delete item"
		copyButton.accessibilityLabel = "Copy item to clipboard"
		shareButton.accessibilityLabel = "Share"
		updateLockButton()
		updateInviteButton()

		openButton.isEnabled = item.canOpen

		dateLabel.text = item.addedString
		dateItem.customView = dateLabelHolder

		if PersistedOptions.darkMode {
			navigationController?.navigationBar.titleTextAttributes = ViewController.shared.navigationController?.navigationBar.titleTextAttributes
		}

		let activity = NSUserActivity(activityType: kGladysDetailViewingActivity)
		activity.title = item.displayTitleOrUuid
		activity.isEligibleForSearch = false
		activity.isEligibleForHandoff = true
		activity.isEligibleForPublicIndexing = false
		userActivity = activity

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(keyboardHiding(_:)), name: .UIKeyboardWillHide, object: nil)
		n.addObserver(self, selector: #selector(keyboardChanged(_:)), name: .UIKeyboardDidChangeFrame, object: nil)
		n.addObserver(self, selector: #selector(updateUI), name: .ExternalDataUpdated, object: nil)
		n.addObserver(self, selector: #selector(updateUI), name: .IngestComplete, object: item)
	}

	private func updateLockButton() {
		if item.isLocked {
			lockButton.accessibilityLabel = "Remove Lock"
			lockButton.image = #imageLiteral(resourceName: "locked")
		} else {
			lockButton.accessibilityLabel = "Lock Item"
			lockButton.image = #imageLiteral(resourceName: "unlocked")
		}
	}

	private func updateInviteButton() {
		invitesButton.isEnabled = CloudManager.syncSwitchedOn
		if item.cloudKitShareRecord == nil {
			invitesButton.accessibilityLabel = "Add People"
			invitesButton.image = #imageLiteral(resourceName: "iconUserAdd")
			deleteButton.isEnabled = true
		} else {
			invitesButton.accessibilityLabel = "People"
			invitesButton.image = #imageLiteral(resourceName: "iconUserChecked")
			deleteButton.isEnabled = true
		}
		deleteButton.isEnabled = !item.sharedFromElsewhere
	}

	@IBAction func inviteButtonSelected(_ sender: UIBarButtonItem) {
		if item.cloudKitShareRecord == nil {
			addInvites(sender)
		} else {
			editInvites(sender)
		}
	}

	@IBAction func lockButtonSelected(_ sender: UIBarButtonItem) {
		if item.isLocked {
			item.unlock(from: self, label: "Remove Lock", action: "Remove") { [weak self] success in
				if success, let s = self {
					s.passwordUpdate(nil, hint: nil)
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						genericAlert(title: "Lock Removed", message: nil, on: s, showOK: false)
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
		activity.userInfo = [kGladysDetailViewingActivityItemUuid: item.uuid]
	}

	@objc private func updateUI() {
		view.endEditing(true)
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

	override var preferredContentSize: CGSize {
		didSet {
			navigationController?.preferredContentSize = preferredContentSize
		}
	}

	@objc private func keyboardHiding(_ notification: Notification) {
		if let u = notification.userInfo, let previousState = u[UIKeyboardFrameBeginUserInfoKey] as? CGRect, !previousState.isEmpty {
			view.endEditing(false)
		}
	}

	@objc private func keyboardChanged(_ notification: Notification) {
		guard let userInfo = notification.userInfo, let keyboardFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

		let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
		let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 0, dy: -additionalSafeAreaInsets.bottom)
		let intersection = safeAreaFrame.intersection(keyboardFrameInView)
		additionalSafeAreaInsets.bottom = intersection.height
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
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
		sizeWindow()
	}

	private var initialWidth: CGFloat = 0

	private func sizeWindow() {
		if sharing {
			preferredContentSize = CGSize(width: 320, height: max(preferredContentSize.height, 500))
		} else {
			table.layoutIfNeeded()
			if initialWidth > 0 {
				preferredContentSize = CGSize(width: initialWidth, height: table.contentSize.height)
			} else {
				preferredContentSize = table.contentSize
			}
		}
		if initialWidth == 0 {
			initialWidth = preferredContentSize.width
		}
	}

	override var keyCommands: [UIKeyCommand]? {
		var a = super.keyCommands ?? []
		a.append(UIKeyCommand(input: "c", modifierFlags: .command, action: #selector(copyPressed), discoverabilityTitle: "Copy Item To Clipboard"))
		return a
	}

	@objc private func copyPressed() {
		copySelected(copyButton)
	}

	var sharing = false
	@IBAction func shareSelected(_ sender: UIBarButtonItem) {
		sharing = true
		sizeWindow()
		let a = UIActivityViewController(activityItems: [item.itemProviderForSharing], applicationActivities: nil)
		a.completionWithItemsHandler = { _, _, _,_ in
			self.sharing = false
			self.sizeWindow()
		}
		present(a, animated: true)
	}

	@IBAction func copySelected(_ sender: UIBarButtonItem) {
		item.copyToPasteboard()
		genericAlert(title: nil, message: "Copied to clipboard", on: self, showOK: false)
	}

	@IBAction func openSelected(_ sender: UIBarButtonItem) {
		item.tryOpen(in: navigationController!) { shouldClose in
			if shouldClose {
				self.done()
			}
		}
	}

	@IBAction func deleteSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Delete Item", style: .destructive, handler: { action in
			self.done()
			if let item = self.item {
				DispatchQueue.main.async {
					ViewController.shared.deleteRequested(for: [item])
				}
			}
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
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

	private static let shortFormatter: DateFormatter = {
		let d = DateFormatter()
		d.doesRelativeDateFormatting = true
		d.dateStyle = .short
		d.timeStyle = .short
		return d
	}()

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		if indexPath.section == 0 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath) as! HeaderCell
			cell.item = item
			cell.resizeCallback = { [weak self] caretRect, heightChange in
				self?.cellNeedsResize(caretRect: caretRect, section: indexPath.section, heightChange: heightChange)
			}
			return cell

		} else if indexPath.section == 1 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as! NoteCell
			cell.item = item
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
			if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
				cell.name.alpha = 1.0
				cell.name.text = "\"\(title)\""
				cell.name.textAlignment = typeEntry.displayTitleAlignment
				setCallbacks(for: cell, for: typeEntry)
			} else if typeEntry.dataExists {
				cell.name.alpha = 0.7
				if typeEntry.isWebArchive {
					cell.name.text = DetailController.shortFormatter.string(from: typeEntry.createdAt)
				} else {
					cell.name.text = "Binary Data"
				}
				cell.name.textAlignment = .center
				setCallbacks(for: cell, for: typeEntry)
			} else {
				cell.name.alpha = 0.7
				cell.name.text = "Loading Error"
				cell.name.textAlignment = .center
				cell.inspectionCallback = nil
				cell.viewCallback = nil
			}
			cell.size.text = typeEntry.sizeDescription
			if showTypeDetails {
				cell.desc.text = typeEntry.typeIdentifier.uppercased()
			} else {
				cell.desc.text = typeEntry.typeDescription.uppercased()
			}

			return cell
		}
	}

	private func setCallbacks(for cell: DetailCell, for typeEntry: ArchivedDropItemType) {

		cell.inspectionCallback = { [weak self] in
			self?.performSegue(withIdentifier: "hexEdit", sender: typeEntry)
		}

		let itemURL = typeEntry.encodedUrl
		if let i = itemURL, !i.isFileURL {
			cell.archiveCallback = { [weak self, weak cell] in
				if let s = self, let c = cell {
					s.archiveWebComponent(cell: c, url: i as URL)
				}
			}
		} else {
			cell.archiveCallback = nil
		}

		if itemURL != nil {
			cell.editCallback = { [weak self] in
				self?.editURL(typeEntry)
			}
		} else if typeEntry.isRichText || typeEntry.isText {
			cell.editCallback = { [weak self] in
				self?.performSegue(withIdentifier: "textEdit", sender: typeEntry)
			}
		} else {
			cell.editCallback = nil
		}

		if typeEntry.canPreview {
			cell.viewCallback = { [weak self] in
				guard let s = self, let q = typeEntry.quickLook(extraRightButton: s.navigationItem.rightBarButtonItem) else { return }
				if PersistedOptions.fullScreenPreviews {
					let n = UINavigationController(rootViewController: q)
					q.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: s, action: #selector(s.closePreview))
					if let sourceBar = s.navigationController?.navigationBar {
						n.navigationBar.titleTextAttributes = sourceBar.titleTextAttributes
						n.navigationBar.barTintColor = sourceBar.barTintColor
						n.navigationBar.tintColor = sourceBar.tintColor
					}
					ViewController.top.present(n, animated: true)
				} else {
					s.navigationController?.pushViewController(q, animated: true)
				}
			}
		} else {
			cell.viewCallback = nil
		}
	}

	private func editURL(_ typeItem: ArchivedDropItemType) {
		getInput(from: self, title: "Edit URL", action: "Change", previousValue: typeItem.encodedUrl?.absoluteString) { [weak self] newValue in
			guard let s = self else { return }
			if let newValue = newValue, let newURL = NSURL(string: newValue) {
				typeItem.replaceURL(newURL)
				s.item.needsReIngest = true
				s.makeIndexAndSaveItem()
				s.table.reloadData()
			} else if newValue != nil {
				genericAlert(title: "This is not a valid URL", message: newValue, on: s) { [weak self] in
					self?.editURL(typeItem)
				}
			}
		}
	}

	@objc private func closePreview() {
		ViewController.top.dismiss(animated: true)
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
		let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] action, view, handler in
			self?.deleteRowSelected(at: indexPath)
			handler(true)
		}
		return UISwipeActionsConfiguration(actions: [delete])
	}

	private func deleteRowSelected(at indexPath: IndexPath) {
		if indexPath.section == 2 {
			item.labels.remove(at: indexPath.row)
			table.deleteRows(at: [indexPath], with: .automatic)
			view.setNeedsLayout()
			makeIndexAndSaveItem()
			item.postModified()
		} else {
			removeTypeItem(at: indexPath)
		}
	}

	private func copyRowSelected(at indexPath: IndexPath) {
		let typeItem = item.typeItems[indexPath.row]
		typeItem.copyToPasteboard()
		genericAlert(title: nil, message: "Copied to clipboard", on: self, showOK: false)
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
		Model.save()
		DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
			self.sizeWindow()
			UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.table)
		}
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
			p.delegate = self
			if PersistedOptions.darkMode {
				p.backgroundColor = ViewController.darkColor
			}
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
		if let d = destinationIndexPath, let s = session.localDragSession {
			if d.section == 2, d.row < item.labels.count, session.canLoadObjects(ofClass: String.self) {
				return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
			}
			if d.section == 3, s.localContext as? String == "typeItem" {
				return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
			}
		}
		return UITableViewDropProposal(operation: .cancel)
	}

	func tableView(_ tableView: UITableView, dropSessionDidExit session: UIDropSession) {
		if session.localDragSession != nil {
			done()
		}
	}

	func tableView(_ tableView: UITableView, dropSessionDidEnter session: UIDropSession) {
		if session.localDragSession == nil {
			done()
		}
	}

	private func makeIndexAndSaveItem() {
		item.markUpdated()
		item.reIndex()
		Model.save()
	}

	func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {

		for coordinatorItem in coordinator.items {
			let dragItem = coordinatorItem.dragItem
			if dragItem.localObject != nil {
				guard
					let destinationIndexPath = coordinator.destinationIndexPath,
					let previousIndex = coordinatorItem.sourceIndexPath else { return }

				if destinationIndexPath.section == 2 {
					let existingLabel = dragItem.localObject as? String
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
						_ = dragItem.itemProvider.loadObject(ofClass: String.self, completionHandler: { newLabel, error in
							if let newLabel = newLabel {
								DispatchQueue.main.async {
									self.item.labels[destinationIndexPath.row] = newLabel
									tableView.performBatchUpdates({
										tableView.reloadRows(at: [destinationIndexPath], with: .automatic)
									})
									self.makeIndexAndSaveItem()
								}
							}
						})
					} else {
						makeIndexAndSaveItem()
					}

				} else if destinationIndexPath.section == 3, previousIndex.section == 3 {

					let destinationIndex = destinationIndexPath.row
					let sourceItem = item.typeItems[previousIndex.row]
					item.typeItems.remove(at: previousIndex.row)
					item.typeItems.insert(sourceItem, at: destinationIndex)
					item.renumberTypeItems()
					table.performBatchUpdates({
						table.moveRow(at: previousIndex, to: destinationIndexPath)
					}, completion: { _ in
						self.makeIndexAndSaveItem()
					})
				}
				coordinator.drop(dragItem, toRowAt: destinationIndexPath)
			}
		}
	}

	private func dragParameters(for indexPath: IndexPath) -> UIDragPreviewParameters? {
		let cell = table.cellForRow(at: indexPath)
		if let cell = cell as? DetailCell {
			let path = UIBezierPath(roundedRect: cell.borderView.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
			let p = UIDragPreviewParameters()
			p.backgroundColor = .clear
			p.visiblePath = path
			return p
		} else if let cell = cell as? LabelCell {
			let path = UIBezierPath(roundedRect: cell.labelHolder.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
			let p = UIDragPreviewParameters()
			p.backgroundColor = .clear
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
		if UIAccessibilityIsVoiceOverRunning() { // weird hack for word mode
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
		cell.animateArchive(true)
		
		WebArchiver.archiveFromUrl(url) { data, typeIdentifier, error in
			if let error = error {
				DispatchQueue.main.async {
					genericAlert(title: "Archiving failed", message: error.finalDescription, on: self)
				}
			} else if let data = data, let typeIdentifier = typeIdentifier {
				let newTypeItem = ArchivedDropItemType(typeIdentifier: typeIdentifier, parentUuid: self.item.uuid, data: data, order: self.item.typeItems.count)
				DispatchQueue.main.async {
					self.view.endEditing(true)
					self.item.typeItems.append(newTypeItem)
					self.item.markUpdated()
					self.updateUI()
					self.item.needsReIngest = true
					self.item.reIngest(delegate: ViewController.shared)
					if let newCell = self.table.cellForRow(at: IndexPath(row: 0, section: self.table.numberOfSections-1)) {
						UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, newCell)
					}
				}
			}
			DispatchQueue.main.async {
				cell.animateArchive(false)
			}
		}
	}

	func textEditControllerMadeChanges(_ textEditController: TextEditController) {
		table.reloadData()
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
		cloudSharingController.availablePermissions = []
		cloudSharingController.delegate = self
		present(cloudSharingController, animated: true) {}
	}

	func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
		genericAlert(title: "Could not share this item", message: error.finalDescription, on: self)
	}

	func itemTitle(for csc: UICloudSharingController) -> String? {
		return item.displayTitleOrUuid
	}

	func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
		item.cloudKitShareRecord = csc.share
		updateInviteButton()
	}

	func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
		item.cloudKitShareRecord = nil
		updateInviteButton()
	}

	func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
		if let ip = item.imagePath {
			return try? Data(contentsOf: ip)
		}
		return nil
	}
}
