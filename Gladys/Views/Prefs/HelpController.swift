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
    
    private struct Entry {
        let title: String
        let body: String
        let link: String?
    }
    
    private let entries = [
        Entry(title: "Shortcut Menus",
              body: """
                    You can bring up shortcut menus for items with a force-press (or long-tap) on their icon. Tapping on an item's preview above its menu will expand it into the full Quick Look view.

                    Shortcut menus are currently available on:

                    • Items in the main view.
                    • Data components inside an item's info view.
                    • Labels in the label selector.

                    If you use a hardware keyboard you can bring up menus instantly by holding down CTRL while selecting an item, and of course if you use a trackpad or mouse you can CTRL-click or right-click.
                    """,
              link: nil),
        
        Entry(title: "Multiple Selection",
              body: "Gladys supports the standard system selection gestures, so you can select multiple items by switching into edit mode and dragging across items, or immediately start swiping with two fingers across items, which will auto-activate edit mode.",
              link: nil),
        
        Entry(title: "Pinch-To-Preview",
              body: """
                    If an item can be previewed with Quick Look, such as an image or PDF, then you can quickly open its preview by pinching out from the item.

                    If you prefer to have previews always open full-screen you can set this at the options panel.
                    """,
              link: nil),
        
        Entry(title: "Labels",
              body: """
                    If you drag-in or paste items while having some active labels, the items will have those labels auto-assigned to them. You can change this behaviour from the options panel.

                    You can drag text items, or text data components, to the label area of an item's info panel to create a new label with that text.

                    Force-press or tap-and-hold on a label in the label selector to get more options, such as:

                    • Renaming a label across all items.
                    • Deleting the label from all item.
                    • Opening a new window with items for that label on iPad.

                    iPad will remember what labels or search are active on each window, so you can keep multiple windows open with assigned labels to act like specific folders.
                    """,
              link: nil),
        
        Entry(title: "Data Components",
              body: """
                    When an item is added to Gladys, it can be provided by the sending app as one or more formats and representations, and they appear as the entries inside an item's info panel.

                    Each data component is like a draggable mini-item, and you may prefer to use them for tasks that require specific data types (for example, you may want to provide JPEG data specifically from an item that includes multiple formats, or extract just the text component from an item that may also include HTML.)

                    Components can be individually previewed with QuickLook if supported, and also edited if they are a form of text or URL. URL components have a download option that can create a web archive of the page a URL points to, if possible. Advanced users can inspect component raw binary data directly with the in-built hex viewer.

                    Force-press or tap-and-hold on a component to get options for:

                    • Deleting it.
                    • Copy only that component to the clipboard, instead of the whole item.

                    Drag data components out of an item's info panel in order to create a stand-alone item with just that component.

                    Alternatively, you can drag a data component out of an info panel, and while dragging it, open other items' info panels and drop it there. This will add a copy of this data component to their existing components, such as adding a URL to an image for example.
                    """,
              link: nil),
        
        Entry(title: "Extensions",
              body: """
                    The 'Keep in Gladys' share-sheet extension can be used from inside apps that don't support drag-and-drop. Please bear in mind that the type of data which is sent using this method may be less detailed than the data that is provided by drag-and-drop.

                    The Apple Watch app allows for quick browsing, copying, or deleting of the top 100 items. Force-press an item to bring up its options, such as copying it to the clipboard, deleting it, moving it to the top of your collection, or opening the item's info panel on your phone.

                    The Today Widget allows fast access to recently added items from the home screen. You can tap on an item to quickly copy it to the clipboard. Tapping and holding on an item will launch Gladys and open the item's details. On iPad you can drag an item off to paste it in another app.

                    The iMessage app allows you to quickly search and add an item from Gladys to a message.
                    """,
              link: nil),
        
        Entry(title: "Siri Shortcuts",
              body: """
                    Gladys supports shortcuts to:

                    • Paste the current clipboard into your collection.
                    • Copy Gladys items directly to the clipboard.
                    • Quick look supported item previews.
                    • Return to specific info panels.

                    You can configure shortcuts for any time directly from its context menu. You can configure the paste action from the mic icon in the options view. Siri may also occasionally suggest shortcuts on the lockscreen for often-used actions based on your usage (as always, all data and processing related to this feature remains strictly on your own device.)
                    """,
              link: nil),
        
        Entry(title: "Sharing",
              body: """
                    If you're using iCloud sync, you can chose to share individual items with other Gladys users via iCloud sharing.

                    You can find the sharing options on the top-right of any item's info panel when iCloud sync is turned on.

                    You can choose to share with specific users or you can generate a public URL for anyone to participate. You can also choose if you'd like your shared item to be editable only by you, or editable by everyone in the share group.

                    When you un-share or delete a shared item, it's removed from all participants' collections (but be aware that others could have still made copies of it in the meantime.)
                    """,
              link: nil),
        
        Entry(title: "Windows",
              body: """
                    On iPad, selecting the window option on the top right of the main view will create a clone of it as a new window. Tapping on the Gladys icon in the Dock will bring up, and let you manage, all created windows. This is supported for:

                    • The main item window: Each one will persist its own search and label terms. Dragging items between windows will add the labels in effect to the items that are dragged in, exactly the same way that new items are assigned the active labels when added the first time.
                    • Quick Look previews: Each one can live in their own window to help compare or refer to them while doing something else, and reduce the need to open supported items like PDFs in a separate app.
                    • Item detail views: Having a separate window can make it much easier to perform long-running or detailed data component operations or inspections.

                    Opening windows works great in combination with slide-over, where, for instance, you can set up various Gladys windows with separate labels for quick access, and to move data between them in a visual folder-like manner.
                    """,
              link: nil),
        
        Entry(title: "Callback URL Support",
              body: """
                    Gladys supports the x-callback-url scheme for automation and interoperability. Currently it supports two main actions:

                    • 'paste-clipboard' to paste existing items from the clipboard.
                    • 'create-item' to create new items with various properties.

                    You can get more details about the x-callback-url scheme support, and info about the parameters and syntax, by selecting this entry.
                    """,
              link: "http://www.bru.build/gladys-callback-scheme"),
        
        Entry(title: "Privacy",
              body: """
                    Gladys does not monitor or report anything at all. You can find a detailed description of the privacy policy on the Gladys web site from the link in the About panel, or by selecting this entry.
                    """,
              link: "http://www.bru.build/apps/gladys/privacy"),
        
        Entry(title: "macOS",
              body: """
                    If you use a Mac, you may find Gladys for the Mac to be a valuable companion to this app.

                    • A fully-fledged version of Gladys for macOS that matches almost every feature.
                    • It's a totally native macOS app that follows the conventions of the Mac desktop.
                    • Syncs with Gladys on iOS.

                    Find more about it by selecting this entry.
                    """,
              link: "http://www.bru.build/gladys-for-macos")
    ]

	override func viewDidLoad() {
		super.viewDidLoad()
		doneButtonLocation = .right
		table.backgroundView = nil
		table.backgroundColor = .clear
        table.tintColor = UIColor(named: "colorTint")
	}

	func numberOfSections(in tableView: UITableView) -> Int {
        return entries.count
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "HelpControllerCell", for: indexPath) as! HelpControllerCell
		let hasLink = entries[indexPath.section].link != nil
		cell.selectionStyle = hasLink ? .default : .none
		cell.accessoryType = hasLink ? .disclosureIndicator : .none
        cell.label.text = entries[indexPath.section].body
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let urlString = entries[indexPath.section].link {
			let d = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading…"
			d.address = URL(string: urlString)
			navigationController?.pushViewController(d, animated: true)
			tableView.deselectRow(at: indexPath, animated: true)
		}
	}
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let v = view as? UITableViewHeaderFooterView {
            v.textLabel?.textColor = table.tintColor
        }
    }

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return entries[section].title
	}
}
