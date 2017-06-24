
import UIKit

final class DetailController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	var item: ArchivedDropItem!

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var header: UIView!

	override func viewDidLoad() {
		super.viewDidLoad()
		table.estimatedRowHeight = 120
		table.rowHeight = UITableViewAutomaticDimension

		titleLabel.text = item.displayInfo.accessoryText ?? item.displayInfo.title
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
		} else {
			cell.name.text = "<Binary Data>"
		}
		cell.type.text = typeEntry.contentDescription
		cell.size.text = typeEntry.sizeDescription
		return cell
	}

}
