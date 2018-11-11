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

	var darkMode = false {
		didSet {
			if darkMode {
				label.textColor = .lightGray
			} else {
				label.textColor = .darkGray
			}
		}
	}
}

final class HelpController: GladysViewController, UITableViewDataSource, UITableViewDelegate {

	@IBOutlet private weak var table: UITableView!

	override func viewDidLoad() {
		super.viewDidLoad()
		doneLocation = .right
		table.backgroundView = nil
		table.backgroundColor = .clear
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		table.reloadData()
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return 10
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "HelpControllerCell", for: indexPath) as! HelpControllerCell
		let hasLink = link(for: indexPath.section) != nil
		cell.selectionStyle = hasLink ? .default : .none
		cell.accessoryType = hasLink ? .disclosureIndicator : .none
		cell.label.text = text(for: indexPath.section)
		cell.darkMode = PersistedOptions.darkMode
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if let urlString = link(for: indexPath.section) {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.address = URL(string: urlString)
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
		case 6: return "Sharing"
		case 7: return "Callback URL Support"
		case 8: return "Privacy"
		case 9: return "macOS Version"
		default: return nil
		}
	}

	private func text(for section: Int) -> String? {
		switch section {
		case 0: return "You can bring up an action menu for items in any of the following ways:\n\n - Tap on an item with two fingers (iPad)\n - Force-press on an item (iPhone)\n - Swipe left on an item (any device)"
		case 1: return "If an item can be previewed with QuickLook, such as an image or PDF, then you can quickly open its preview by pinching out from the item.\n\nIf you prefer to have previews always open full-screen you can set this at the options panel."
		case 2: return "Swipe left to delete a label from the info panel of an item.\n\nIf you drag-in or paste items while having set some active labels, those items will have those labels auto-assigned to them. You can change this setting from the options panel.\n\nTo delete a label from all items that contain it, you can swipe to delete it from the labels popup on the top-right of the main view.\n\nYou can drag text items, or data components to the label area of an item's info panel to create a new label with that text."
		case 3: return "Data components are the entries inside an item's info panel. They can be one or more formats and representations of the dropped item, as provided by the original app.\n\nComponents can be individually previewed with QuickLook if supported, and also edited if they are a form of text or URL. URL components have a download option that can create a web archive of the page a URL points to, if possible. Advanced users can inspect component raw binary data directly with the in-built hex viewer.\n\nSwipe data components to the left to delete them.\n\nSwipe data components to the right to copy only that component to the clipboard, instead of the whole item.\n\nDrag data components out of an item's info panel in order to create a stand-alone item with just that component.\n\nAlternatively, you can drag a data component out of an info panel, and while dragging it, open other items' info panels and drop it there. This will add a copy of this data component to their existing components, such as adding a URL to an image for example."
		case 4: return "The 'Keep in Gladys' share-sheet extension can be used from inside apps that don't support drag-and-drop. Please bear in mind that the type of data which is sent using this method may be less detailed than the data that is provided by drag-and-drop.\n\nThe Apple Watch app allows for quick browsing, copying, or deleting of recent items. Force-press an item to bring up its options, such as copying it to the clipboard, deleting it, moving it to the top of your collection, or opening the item's info panel on your phone.\n\nThe Today Widget allows fast access to recently added items from the home screen. You can tap on an item to quickly copy it to the clipboard.\n\nThe iMessage app allows you to quickly search and add an item from Gladys to a message."
		case 5: return "Gladys exports a shortcut to paste the current clipboard into your collection, but also donates a shortcut when you copy or drag items out of it, so you can automate an item's copying in the future.\n\nYou can also quickly return to info panels or item previews that you previously opened in the main item list.\n\nYou can create voice commands in the Siri section of your device settings for these shortcuts, and Siri may also suggest often-used ones based on your usage on the lockscreen.\n\nYou can manage (or disable) Siri shortcuts and/or suggestions from the 'Settings' app. As always, all data and processing related to this feature remains strictly on your own device."
		case 6: return "If you're using iCloud sync, you can chose to share individual items with other Gladys users via iCloud sharing.\n\nYou can find the sharing options on the top-right of any item's info panel when iCloud sync is turned on.\n\nYou can choose to share with specific users or you can generate a public URL for anyone to participate. You can also choose if you'd like your shared item to be editable only by you, or editable by everyone in the share group.\n\nWhen you un-share or delete a shared item, it's removed from all participants' collections (but be aware that others could have still made copies of it in the meantime.)"
		case 7: return "Gladys supports the x-callback-url scheme for interoperability with other apps.\n\nCurrently it supports two actions: 'paste-clipboard', and 'create-item' to paste items from the clipboard and also create simple text items, respectively.\n\nYou can get more details about the x-callback-url scheme support, and info about the parameters and syntax, by selecting this entry."
		case 8: return "Gladys does not monitor or report anything at all. You can find a detailed description of the privacy policy on the Gladys web site from the link in the About panel, or by selecting this entry."
		case 9: return "If you also use a Mac, you may find Gladys for the Mac to be a valuable companion to this app.\n\n• A fully-fledged version of Gladys for macOS that matches almost every feature.\n• It's a totally native macOS app that follows the conventions of the Mac desktop.\n• Syncs with Gladys on iOS.\n\nFind more about it by selecting this entry."
		default: return nil
		}
	}

	private func link(for section: Int) -> String? {
		switch section {
		case 7: return "http://www.bru.build/gladys-callback-scheme"
		case 8: return "http://www.bru.build/apps/gladys/privacy"
		case 9: return "http://www.bru.build/gladys-for-macos"
		default: return nil
		}
	}
}
