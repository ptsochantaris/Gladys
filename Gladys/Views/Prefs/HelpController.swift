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

	@IBOutlet private weak var table: UITableView!

	override func viewDidLoad() {
		super.viewDidLoad()
		doneLocation = .right
		table.backgroundView = nil
		table.backgroundColor = .clear
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return 8
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
		resizer.text = text(for: indexPath.section)
		let h = resizer.systemLayoutSizeFitting(CGSize(width: s.width - 30, height: 5000),
												withHorizontalFittingPriority: .required,
												verticalFittingPriority: .fittingSizeLevel).height
		return h.rounded(.up) + 30
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "HelpControllerCell", for: indexPath) as! HelpControllerCell
		cell.label.text = text(for: indexPath.section)
		cell.selectionStyle = indexPath.section == 7 ? .default : .none
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.section == 8 {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.address = URL(string: "http://www.bru.build/gladys-for-macos")
			navigationController?.pushViewController(d, animated: true)
			tableView.deselectRow(at: indexPath, animated: true)
		}
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case 0: return "Shortcut Menu"
		case 1: return "Pinch-To-Preview"
		case 2: return "Labels"
		case 3: return "Data Components"
		case 4: return "Extensions"
		case 5: return "Siri Shortcuts"
		case 6: return "Callback URL Support"
		case 7: return "Privacy"
		case 8: return "macOS Version"
		default: return nil
		}
	}

	private func text(for section: Int) -> String? {
		switch section {
		case 0: return "You can bring up a shortcut menu with the most common functions in Gladys by either tapping on an item with two fingers (iPad) or force-pressing on an item (iPhone)"
		case 1: return "If an item can be previewed with QuickLook, such as an image or PDF, then you can quickly open its preview by pinching out from the item.\n\nIf you prefer to have previews always open full-screen you can set this from the options panel."
		case 2: return "Swipe left to delete a label from the info view of an item.\n\nIf you drag-in or paste items while having set some active labels, those items will have those labels auto-assigned to them. You can change this setting from the options panel.\n\nTo delete a label from all items that contain it, you can swipe to delete it from the labels popup on the top-right.\n\nYou can drag text items, or data components to the label area of an item's info view to create a new label with that text."
		case 3: return "Data components are the entries inside an item's info view.\n\nSwipe data components to the left to delete them.\n\nSwipe data components to the right to copy only that component to the clipboard instead of the whole item.\n\nDrag data components out of an item's info view in order to create a stand-alone item with just that component.\n\nAlternatively, if you activate 'Allow Merging' in options, you can drag a data component into other items to merge it with their existing data components, such as adding a URL to an image for example."
		case 4: return "The 'Keep in Gladys' share-sheet extension can be used from inside apps that don't support drag-and-drop. Please bear in mind that the type of data which is sent using this method may be less detailed than the data that is provided by drag-and-drop.\n\nThe Apple Watch app allows for quick browsing, copying, or deleting of recent items. Force-press an item to bring up its options, such as copying it to the clipboard, deleting it, moving it to the top of your collection, or opening the item's info view on your phone.\n\nThe Today Widget allows fast access to recently added items from the home screen. You can tap on an item to quickly copy it to the clipboard.\n\nThe iMessage app allows you to quickly search and add an item from Gladys to a message."
		case 5: return "You can use Siri on iOS 12 to return to often-visited items, or item previews that you opened from the main item list.\n\nYou can create voice commands in the 'Shortcuts' app for items you wish to quickly return to or preview often, and Siri can also suggest often-used items based on your usage on the lockscreen.\n\nYou can manage (or disable) Siri shortcuts and/or suggestions from the 'Settings' and 'Shortcuts' apps.\n\nAs always, all data and processing related to this feature remains strictly on your own device."
		case 6: return "Gladys supports the x-callback-url scheme for interoperability with other apps.\n\nCurrently it supports one action: 'paste-clipboard', and you can invoke it like this:\n\ngladys://x-callback-url/paste-clipboard\n?title=Override%20The%20Title\n&labels=Pasted%20Item,New%20Items\n&note=Some%20Notes\n\nAll the parameters are optional, but be sure to properly url-encode special characters, such as spaces. The callbacks support x-success and x-error parameters."
		case 7: return "Gladys does not monitor or report anything at all. You can find a detailed description of the privacy policy on the Gladys web site from the link in the About panel."
		case 8: return "If you also use a Mac, you may find Gladys for the Mac to be a valuable companion to this app.\n\n• A fully-fledged version of Gladys for macOS that matches almost every feature.\n• It's a totally native macOS app that follows the conventions of the Mac desktop.\n• Syncs with Gladys on iOS.\n\nFind more about it by selecting this entry."
		default: return nil
		}
	}
}
