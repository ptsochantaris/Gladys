
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
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		table.layoutIfNeeded()
		preferredContentSize = table.contentSize
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}

	@IBAction func shareSelected(_ sender: UIBarButtonItem) {
		let a = UIActivityViewController(activityItems: item.shareableComponents, applicationActivities: nil)
		preferredContentSize = CGSize(width: 320, height: 600)
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
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return item.typeItems.count + 1
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section > 0 {
			return item.typeItems[section-1].contentDescription
		} else {
			return nil
		}
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		if indexPath.section == 0 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath) as! HeaderCell
			cell.label.text = item.oneTitle
			cell.label.textAlignment = item.displayTitle.1
			return cell

		} else {

			let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath) as! DetailCell
			let typeEntry = item.typeItems[indexPath.section-1]
			if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
				cell.name.text = "\"\(title)\""
				cell.name.textAlignment = typeEntry.displayTitleAlignment
			} else if typeEntry.dataExists {
				cell.name.text = "<Binary Data>"
			} else {
				cell.name.text = "<Data Error>"
			}
			cell.type.text = typeEntry.typeIdentifier
			cell.size.text = typeEntry.sizeDescription
			return cell
		}
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		if section == 0 {
			return 20
		} else {
			return 34
		}
	}

	func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		if indexPath.section > 0 {
			let typeItem = item.typeItems[indexPath.section-1]
			return [typeItem.dragItem]
		} else {
			return []
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

	func reload() {
		table.reloadData()
	}

	func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}
}
