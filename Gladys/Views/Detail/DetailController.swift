
import UIKit

final class DetailController: GladysViewController,
	UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate,
	UIPopoverPresentationControllerDelegate, AddLabelControllerDelegate {

	var item: ArchivedDropItem!

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var openButton: UIBarButtonItem!
	@IBOutlet weak var dateItem: UIBarButtonItem!
	@IBOutlet weak var dateLabel: UILabel!
	@IBOutlet weak var dateLabelHolder: UIView!
	@IBOutlet weak var deleteButton: UIBarButtonItem!
	@IBOutlet weak var copyButton: UIBarButtonItem!
	@IBOutlet weak var shareButton: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()
		table.estimatedRowHeight = 120
		table.rowHeight = UITableViewAutomaticDimension
		table.dragInteractionEnabled = true
		table.dragDelegate = self
		table.dropDelegate = self
		table.dragInteractionEnabled = true

		deleteButton.accessibilityLabel = "Delete item"
		copyButton.accessibilityLabel = "Copy item to clipboard"
		shareButton.accessibilityLabel = "Share"

		openButton.isEnabled = item.canOpen

		dateLabel.text = "Added " + dateFormatter.string(from: item.createdAt) + "\n" + diskSizeFormatter.string(fromByteCount: item.sizeInBytes)
		dateItem.customView = dateLabelHolder

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(keyboardHiding(_:)), name: .UIKeyboardWillHide, object: nil)
		n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
	}

	@objc private func externalDataUpdate() {
		table.reloadData()
		sizeWindow()
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

	deinit {
		NotificationCenter.default.removeObserver(self)
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

	private func sizeWindow() {
		if sharing {
			preferredContentSize = CGSize(width: 320, height: max(preferredContentSize.height, 500))
		} else {
			table.layoutIfNeeded()
			preferredContentSize = table.contentSize
		}
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}

	var sharing = false
	@IBAction func shareSelected(_ sender: UIBarButtonItem) {
		sharing = true
		sizeWindow()
		let a = UIActivityViewController(activityItems: item.shareableComponents, applicationActivities: nil)
		a.completionWithItemsHandler = { _, _, _,_ in
			self.sharing = false
			self.sizeWindow()
		}
		present(a, animated: true)
	}

	@IBAction func copySelected(_ sender: UIBarButtonItem) {
		item.copyToPasteboard()
		let a = UIAlertController(title: nil, message: "Copied to clipboard", preferredStyle: .alert)
		present(a, animated: true)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			a.dismiss(animated: true)
		}
	}

	@IBAction func openSelected(_ sender: UIBarButtonItem) {
		item.tryOpen(in: navigationController!)
	}

	@IBAction func deleteSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Delete Item", style: .destructive, handler: { action in
			ViewController.shared.deleteRequested(for: [self.item])
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	//////////////////////////////////

	func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	//////////////////////////////////

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 2 {
			return item.labels.count + 1
		}
		return 1
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return item.typeItems.count + 3
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section < 2 {
			return nil
		} else if section == 2 {
			return "Labels"
		} else {
			return item.typeItems[section-3].contentDescription
		}
	}

	private func cellNeedsResize(caretRect: CGRect?) {
		UIView.setAnimationsEnabled(false)
		table.beginUpdates()
		if let caretRect = caretRect {
			table.scrollRectToVisible(caretRect, animated: false)
		} else {
			table.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
		}
		table.endUpdates()
		UIView.setAnimationsEnabled(true)
		sizeWindow()
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		if indexPath.section == 0 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath) as! HeaderCell
			cell.item = item
			cell.resizeCallback = { [weak self] caretRect in
				self?.cellNeedsResize(caretRect: caretRect)
			}
			return cell

		} else if indexPath.section == 1 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as! NoteCell
			cell.item = item
			cell.resizeCallback = { [weak self] caretRect in
				self?.cellNeedsResize(caretRect: caretRect)
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
			let typeEntry = item.typeItems[indexPath.section-3]
			if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
				cell.name.alpha = 1.0
				cell.name.text = "\"\(title)\""
				cell.name.textAlignment = typeEntry.displayTitleAlignment
				cell.selectionCallback = nil
			} else if typeEntry.dataExists {
				cell.name.alpha = 0.7
				cell.name.text = "Binary Data"
				cell.name.textAlignment = .center
				cell.selectionCallback = { [weak self] in
					self?.performSegue(withIdentifier: "hexEdit", sender: typeEntry)
				}
			} else {
				cell.name.alpha = 0.7
				cell.name.text = "Loading Error"
				cell.name.textAlignment = .center
				cell.selectionCallback = nil
			}
			cell.type.text = typeEntry.typeIdentifier
			cell.size.text = typeEntry.sizeDescription
			return cell
		}
	}

	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
		if indexPath.section == 2 && indexPath.row < item.labels.count {
			return .delete
		}
		return .none
	}

	func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == .delete {
			item.labels.remove(at: indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .automatic)
			makeIndexAndSaveItem()
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "hexEdit",
			let typeEntry = sender as? ArchivedDropItemType,
			let e = segue.destination as? HexEdit {
			
			e.bytes = typeEntry.bytes ?? Data()
			
			let f = ByteCountFormatter()
			let size = f.string(fromByteCount: Int64(e.bytes.count))
			e.title = typeEntry.contentDescription + " (\(size))"

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
		if section < 2 {
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
				return [i]
			} else {
				return []
			}
		} else {
			let typeItem = item.typeItems[indexPath.section-3]
			return [typeItem.dragItem]
		}
	}

	func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
		if let d = destinationIndexPath,
			d.section == 2,
			d.row < item.labels.count,
			session.canLoadObjects(ofClass: String.self),
			session.localDragSession != nil {

			return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
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
		item.makeIndex() { _ in
			ViewController.shared.model.save()
		}
	}

	func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {

		for coordinatorItem in coordinator.items {
			let dragItem = coordinatorItem.dragItem
			if dragItem.localObject != nil {
				guard
					let destinationIndexPath = coordinator.destinationIndexPath,
					let previousIndex = coordinatorItem.sourceIndexPath else { return }

				let existingLabel = dragItem.localObject as? String
				if previousIndex.section == 2 {
					item.labels.remove(at: previousIndex.row)
					item.labels.insert(existingLabel ?? "...", at: destinationIndexPath.row)
					tableView.performBatchUpdates({
						tableView.reloadData()
					})
				} else {
					item.labels.insert(existingLabel ?? "...", at: destinationIndexPath.row)
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
					self.makeIndexAndSaveItem()
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
		guard indexPath.section == 2 else {
			tableView.deselectRow(at: indexPath, animated: false)
			return
		}

		performSegue(withIdentifier: "addLabel", sender: indexPath)
	}

	func addLabelController(_ addLabelController: AddLabelController, didEnterLabel: String?) {

		guard let indexPath = self.table.indexPathForSelectedRow else { return }
		table.deselectRow(at: indexPath, animated: true)

		guard let didEnterLabel = didEnterLabel, !didEnterLabel.isEmpty else { return }

		if indexPath.row < self.item.labels.count {
			self.item.labels[indexPath.row] = didEnterLabel
			self.table.reloadRows(at: [indexPath], with: .automatic)
		} else {
			self.item.labels.append(didEnterLabel)
			self.table.insertRows(at: [indexPath], with: .automatic)
		}
		self.makeIndexAndSaveItem()
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}
}
