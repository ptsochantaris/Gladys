
import UIKit

final class DetailController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate {

	var item: ArchivedDropItem!

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var header: UIView!
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

		titleLabel.text = item.oneTitle
		titleLabel.textAlignment = item.displayInfo.titleAlignment
		openButton.isEnabled = item.canOpen

		dateLabel.text = "Added " + dateFormatter.string(from: item.createdAt) + "\n" + diskSizeFormatter.string(fromByteCount: item.sizeInBytes)
		dateItem.customView = dateLabelHolder

		table.backgroundColor = .clear
		table.separatorStyle = .none
		view.backgroundColor = .clear
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		let newSize = header.systemLayoutSizeFitting(CGSize(width: view.bounds.size.width, height: 0),
		                                             withHorizontalFittingPriority: .required,
		                                             verticalFittingPriority: .fittingSizeLevel)
		header.frame = CGRect(origin: .zero, size: newSize)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		preferredContentSize = table.sizeThatFits(CGSize(width: 320, height: 5000))
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		dismiss(animated: true)
	}

	@IBAction func shareSelected(_ sender: UIBarButtonItem) {
		let a = UIActivityViewController(activityItems: item.shareableComponents, applicationActivities: nil)
		present(a, animated: true)
	}

	@IBAction func openSelected(_ sender: UIBarButtonItem) {
		item.tryOpen(in: self.navigationController!)
	}

	@IBAction func deleteSelected(_ sender: UIBarButtonItem) {
		dismiss(animated: true) {
			NotificationCenter.default.post(name: .DeleteSelected, object: self.item)
		}
	}

	//////////////////////////////////
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return item.typeItems.count
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return item.typeItems[section].typeIdentifier
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath) as! DetailCell
		let typeEntry = item.typeItems[indexPath.section]
		if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
			cell.name.text = "\"\(title)\""
			cell.name.textAlignment = typeEntry.displayTitleAlignment
		} else if typeEntry.dataExists {
			cell.name.text = "<Binary Data>"
		} else {
			cell.name.text = "<Data Error>"
		}
		cell.type.text = typeEntry.contentDescription
		cell.size.text = typeEntry.sizeDescription
		return cell
	}

	func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		let typeItem = item.typeItems[indexPath.section]
		return [typeItem.dragItem]
	}

}
