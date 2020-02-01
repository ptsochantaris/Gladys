import UIKit

final class LabelEditorController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {

	@IBOutlet private weak var labelText: UITextField!
	@IBOutlet private weak var table: UITableView!

	@IBOutlet private var headerView: UIView!
	@IBOutlet private weak var headerLabel: UILabel!

	var selectedLabels = [String]()
	var completion: (([String], String) -> Void)?

	var note = ""

	private lazy var allToggles: [String] = { // lazy is important here, keep
		var labels  = Set<String>()
		for item in Model.drops {
			for label in item.labels {
				labels.insert(label)
			}
		}
		return labels.sorted()
	}()

	private var availableToggles = [String]()

	override func viewDidLoad() {
		super.viewDidLoad()
		updateFilter(nil)
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return min(1, availableToggles.count)
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return availableToggles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelEditorCell", for: indexPath) as! LabelEditorCell

		let toggle = availableToggles[indexPath.row]
		cell.labelName.text = toggle
		cell.accessibilityLabel = toggle

		if selectedLabels.contains(toggle) {
			cell.tick.isHidden = false
			cell.tick.isHighlighted = true
			cell.accessibilityValue = "Selected"
		} else {
			cell.tick.isHidden = true
			cell.tick.isHighlighted = false
			cell.accessibilityValue = nil
		}
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let toggle = availableToggles[indexPath.row]
		if let i = selectedLabels.firstIndex(of: toggle) {
			selectedLabels.remove(at: i)
		} else {
			selectedLabels.append(toggle)
		}
		tableView.reloadRows(at: [indexPath], with: .none)
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 40
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return headerView
	}

	private func updateFilter(_ text: String?) {
		let filter = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if filter.isEmpty {
			availableToggles = allToggles
		} else {
			availableToggles = allToggles.filter { $0.localizedCaseInsensitiveContains(filter) }
		}
		table.reloadData()
	}

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {

		if string != "\n" {
			if let oldText = textField.text, !oldText.isEmpty, let r = Range(range, in: oldText) {
				let newText = oldText.replacingCharacters(in: r, with: string)
				updateFilter(newText)
			} else {
				updateFilter(nil)
			}
			return true
		}

		textField.resignFirstResponder()

		guard let newTag = textField.text, !newTag.isEmpty else {
			return false
		}

		textField.text = nil
		if !allToggles.contains(newTag) {
			allToggles.append(newTag)
			allToggles.sort()
		}
		updateFilter(nil)
		if let i = allToggles.firstIndex(of: newTag) {
			let existingToggle = allToggles[i]
			let ip = IndexPath(row: i, section: 0)
			if !selectedLabels.contains(existingToggle) {
				tableView(table, didSelectRowAt: ip)
			}
			table.scrollToRow(at: ip, at: .middle, animated: true)
		}
		return false
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		if UIAccessibility.isVoiceOverRunning && labelText.isFirstResponder { // weird hack for word mode
			let left = -scrollView.adjustedContentInset.left
			if scrollView.contentOffset.x < left {
				let top = -scrollView.adjustedContentInset.top
				scrollView.contentOffset = CGPoint(x: left, y: top)
			}
		}

		headerLabel.alpha = 1.0 - min(1, max(0, scrollView.contentOffset.y / 8.0))
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		completion?(selectedLabels, note)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		if let d = segue.destination as? NoteEditorController {
			d.initialNote = note
			d.completion = { [weak self] newNote in
				self?.note = newNote
			}
		}
	}
}
