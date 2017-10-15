//
//  AddLabelController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

protocol AddLabelControllerDelegate: class {
	func addLabelController(_ addLabelController: AddLabelController, didEnterLabel: String?)
}

final class AddLabelController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {

	@IBOutlet weak var labelText: UITextField!

	var label: String?

	weak var delegate: AddLabelControllerDelegate?

	@IBOutlet var headerView: UIView!
	@IBOutlet weak var headerLabel: UILabel!

	override func viewDidLoad() {
		super.viewDidLoad()
		labelText.text = label
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setNavigationBarHidden(true, animated: false)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		labelText.becomeFirstResponder()
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return Model.labelToggles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelListCell") as! LabelListCell
		let toggle = Model.labelToggles[indexPath.row]
		cell.labelName.text = toggle.name
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		labelText.text = Model.labelToggles[indexPath.row].name
		dirty = true
		dismiss(animated: true, completion: nil)
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 40
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return headerView
	}

	private var dirty = false

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			dismiss(animated: true, completion: nil)
			return false
		} else {
			dirty = true
			return true
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		let result = dirty ? labelText.text?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
		dirty = false
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.delegate?.addLabelController(self, didEnterLabel: result)
		}
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		headerLabel.alpha = 2.0 - min(2, max(0, scrollView.contentOffset.y / 48.0))
	}
}
