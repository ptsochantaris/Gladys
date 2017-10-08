
import UIKit

final class DetailController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {

	var item: ArchivedDropItem!

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var openButton: UIBarButtonItem!
	@IBOutlet weak var dateItem: UIBarButtonItem!
	@IBOutlet var dateLabel: UILabel!
	@IBOutlet var dateLabelHolder: UIView!

	override func viewDidLoad() {
		super.viewDidLoad()
		table.estimatedRowHeight = 120
		table.rowHeight = UITableViewAutomaticDimension
		table.dragInteractionEnabled = true
		table.dragDelegate = self
		table.dropDelegate = self

		openButton.isEnabled = item.canOpen

		dateLabel.text = "Added " + dateFormatter.string(from: item.createdAt) + "\n" + diskSizeFormatter.string(fromByteCount: item.sizeInBytes)
		dateItem.customView = dateLabelHolder

		table.backgroundColor = .clear
		table.separatorStyle = .none
		view.backgroundColor = .clear

		NotificationCenter.default.addObserver(self, selector: #selector(keyboardHiding(_:)), name: .UIKeyboardWillHide, object: nil)
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

	@IBAction func openSelected(_ sender: UIBarButtonItem) {
		item.tryOpen(in: navigationController!)
	}

	@IBAction func deleteSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Delete Item", style: .destructive, handler: { action in
			NotificationCenter.default.post(name: .DeleteSelected, object: self.item)
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	//////////////////////////////////

	func reload() {
		table.reloadData()
	}

	func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	//////////////////////////////////

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return item.typeItems.count + 2
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section < 2 {
			return nil
		} else {
			return item.typeItems[section-2].contentDescription
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

		} else {

			let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath) as! DetailCell
			let typeEntry = item.typeItems[indexPath.section-2]
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

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "hexEdit",
			let typeEntry = sender as? ArchivedDropItemType,
			let e = segue.destination as? HexEdit {
			
			e.bytes = typeEntry.bytes ?? Data()
			
			let f = ByteCountFormatter()
			let size = f.string(fromByteCount: Int64(e.bytes.count))
			e.title = (typeEntry.contentDescription ?? typeEntry.oneTitle) + " (\(size))"
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
		} else {
			let typeItem = item.typeItems[indexPath.section-2]
			return [typeItem.dragItem]
		}
	}

	func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
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

	func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {}

	private func dragParameters(for indexPath: IndexPath) -> UIDragPreviewParameters? {
		if let cell = table.cellForRow(at: indexPath) as? DetailCell {
			let path = UIBezierPath(roundedRect: cell.borderView.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
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
}
