//
//  PlistEditor.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 25/11/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import GladysFramework

final class PlistEditorCell: UITableViewCell {
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var subtitleLabel: UILabel!

	@IBOutlet private weak var topDistance: NSLayoutConstraint!
	@IBOutlet private weak var bottomDistance: NSLayoutConstraint!

	var arrayMode = false {
		didSet {
			if arrayMode {
				topDistance.constant = 8
				bottomDistance.constant = 8
			} else {
				topDistance.constant = 2
				bottomDistance.constant = 2
			}
			if PersistedOptions.darkMode {
				titleLabel.textColor = UIColor.lightGray
				subtitleLabel.textColor = UIColor.lightGray
			} else {
				titleLabel.textColor = UIColor.darkText
				subtitleLabel.textColor = UIColor.darkGray
			}
		}
	}
}

final class PlistEditor: GladysViewController, UITableViewDataSource, UITableViewDelegate {
	var propertyList: Any!

	private var arrayMode = false

	@IBOutlet private weak var table: UITableView!
	@IBOutlet private weak var backgroundView: UIImageView!

	override func viewDidLoad() {
		super.viewDidLoad()
		arrayMode = propertyList is [Any]
		table.tableFooterView = UIView(frame: .zero)
		doneLocation = .right
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		backgroundView.image = (ViewController.shared.itemView.backgroundView as! UIImageView).image
		if PersistedOptions.darkMode {
			table.separatorColor = UIColor.darkGray
		} else {
			table.separatorColor = UIColor.lightGray
		}
	}

	private func title(at index: Int) -> String? {
		if propertyList is [Any] {
			return "Item \(index)"
		} else if let p = propertyList as? [AnyHashable: Any] {
			return p.keys.sorted { $0.hashValue < $1.hashValue }[index] as? String ?? "<unkown>"
		} else {
			return nil
		}
	}

	private func value(at index: Int) -> Any? {
		if let p = propertyList as? [Any] {
			return p[index]
		} else if let p = propertyList as? [AnyHashable: Any] {
			let key = p.keys.sorted { $0.hashValue < $1.hashValue }[index]
			return p[key]
		} else {
			return nil
		}
	}

	private func selectable(at index: Int) -> Bool {
		let v = value(at: index)
		if let v = v as? [Any] {
			return v.count > 0
		} else if let v = v as? [AnyHashable: Any] {
			return v.keys.count > 0
		} else if let v = v as? Data {
			return v.count > 0
		}
		return false
	}

	private func description(at index: Int) -> String {
		let v = value(at: index)
		if let v = v as? [Any] {
			let c = v.count
			if c == 0 {
				return "Empty list"
			} else if c == 1 {
				return "List of one item"
			} else {
				return "List of \(c) items"
			}

		} else if let v = v as? [AnyHashable: Any] {
			let c = v.keys.count
			if c == 0 {
				return "Dictionary, empty"
			} else if c == 1 {
				return "Dictionary, 1 item"
			} else {
				return "Dictionary, \(c) items"
			}

		} else if let v = v as? Data {
			let c = v.count
			if c == 0 {
				return "Data, empty"
			} else if c == 1 {
				return "Data, 1 byte"
			} else {
				return "Data, \(c) bytes"
			}

		} else if let v = v as? String {
			if v.isEmpty {
				return "Text, empty"
			} else {
				return "\"\(v)\""
			}

		} else if let v = v as? NSNumber {
			return v.description

		} else if let v = v {
			let desc = String(describing: v)
			if desc.isEmpty {
				return "<no description>"
			} else if desc.contains("CFKeyedArchiverUID") {
				return "CFKeyedArchiverUID: " + String(valueForKeyedArchiverUID(v))
			} else {
				return desc
			}
		}
		return "<unknown>"
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let p = propertyList as? [Any] {
			return p.count
		} else if let p = propertyList as? [AnyHashable: Any] {
			return p.keys.count
		} else {
			abort()
		}
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "PlistEntryCell") as! PlistEditorCell
		cell.accessoryType = selectable(at: indexPath.row) ? .disclosureIndicator : .none
		cell.arrayMode = arrayMode
		let d = description(at: indexPath.row)
		if arrayMode {
			cell.titleLabel.text = d
			cell.subtitleLabel.text = nil
		} else {
			cell.titleLabel.text = title(at: indexPath.row)
			cell.subtitleLabel.text = d
		}
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		if selectable(at: indexPath.row) {
			let v = value(at: indexPath.row)
			if v is [Any] || v is [AnyHashable: Any] {
				let editor = storyboard?.instantiateViewController(withIdentifier: "PlistEditor") as! PlistEditor
				editor.propertyList = v
				editor.title = title(at: indexPath.row)
				navigationController?.pushViewController(editor, animated: true)

			} else if let v = v as? Data {
				performSegue(withIdentifier: "hexEdit", sender: ("Data", v))
			}
		}

		tableView.deselectRow(at: indexPath, animated: true)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		if let destination = segue.destination as? HexEdit, let data = sender as? (String, Data) {
			destination.title = data.0
			destination.bytes = data.1
		}
	}

	///////////////////////////////////

	private var lastSize = CGSize.zero

	override var preferredContentSize: CGSize {
		didSet {
			navigationController?.preferredContentSize = preferredContentSize
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if lastSize != view.frame.size && !view.frame.isEmpty {
			lastSize = view.frame.size
			let H = max(table.contentSize.height, 50)
			preferredContentSize = CGSize(width: preferredContentSize.width, height: H)
		}
	}
}
