//
//  HelpViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class HelpControllerCell: UITableViewCell {
	@IBOutlet weak var label: UILabel!
}

final class HelpController: GladysViewController, UITableViewDataSource, UITableViewDelegate {

	@IBOutlet weak var table: UITableView!

	override func viewDidLoad() {
		super.viewDidLoad()
		doneLocation = .right
		table.backgroundView = nil
		table.backgroundColor = .clear
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return 6
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case 0: return "Shortcut Menu"
		case 1: return "Pinch-To-Preview"
		case 2: return "Auto-Assigning Labels"
		case 3: return "Deleting Labels"
		case 4: return "Callback URL Support"
		case 5: return "Privacy"
		default: return nil
		}
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	private let resizer: UILabel = {
		let l = UILabel()
		l.font = UIFont.preferredFont(forTextStyle: .caption1)
		l.adjustsFontForContentSizeCategory = true
		l.numberOfLines = 0
		l.lineBreakMode = .byWordWrapping
		return l
	}()

	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		let s = view.bounds.size
		resizer.text = label(for: indexPath.section)
		let h = resizer.systemLayoutSizeFitting(CGSize(width: s.width - 30, height: 5000),
												withHorizontalFittingPriority: .required,
												verticalFittingPriority: .fittingSizeLevel).height
		return h.rounded(.up) + 20
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "HelpControllerCell", for: indexPath) as! HelpControllerCell
		cell.label.text = label(for: indexPath.section)
		return cell
	}

	private func label(for section: Int) -> String? {
		switch section {
		case 0: return "You can bring up a shortcut menu with the most common functions in Gladys by either tapping on an item with two fingers (iPad) or force-pressing on an item (iPhone)"
		case 1: return "If an item can be previewed with QuickLook, such as an image or PDF, then you can quickly open its preview by pinching out from it. If you prefer previews to always open full-screen you can set this from the options panel."
		case 2: return "If you drag or paste items while having active labels, those items will get those labels auto-assigned to them. You can change this setting from the options panel."
		case 3: return "You can swipe to delete a label from the info view of an item.\n\nIf you want to delete a label from all items that contain it, you can swipe to delete it from the labels popup and selecting 'Delete'."
		case 4: return "Gladys supports the x-callback-url scheme for being called from other apps.\n\nCurrently it supports one action: 'paste-clipboard', and you can invoke it like this:\n\ngladys://x-callback-url/paste-clipboard\n?title=Override%20The%20Title\n&labels=Pasted%20Item,New%20Items\n&note=Some%20Notes\n\nAll the parameters are optional, but be sure to properly url-encode special characters, such as spaces."
		case 5: return "Gladys does not monitor or report anything at all, and never will. You can find a detailed description of the privacy policy on the Gladys web site that's linked from the About panel."
		default: return nil
		}
	}
}
