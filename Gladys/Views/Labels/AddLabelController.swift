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

	override func viewDidLoad() {
		super.viewDidLoad()
		labelText.text = label
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.preferredContentSize = CGSize(width: preferredContentSize.width, height: 240)
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
		labelText.resignFirstResponder()
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 40
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return headerView
	}

	private var dirty = false
	private var finished = false

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
			return false
		} else {
			dirty = true
			return true
		}
	}

	func textFieldDidEndEditing(_ textField: UITextField) {
		let result = dirty ? labelText.text?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
		delegate?.addLabelController(self, didEnterLabel: result)
		dirty = false
	}

	override func viewWillDisappear(_ animated: Bool) {
		let result = dirty ? labelText.text?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
		delegate?.addLabelController(self, didEnterLabel: result)
		dirty = false
	}
}
