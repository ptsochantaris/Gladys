//
//  NotesEditorViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 02/12/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

protocol NotesEditorViewControllerDelegate: class {
	func newNoteSaved(note: String)
}

final class NotesEditorViewController: GladysViewController {

	var startupNote: String?
	weak var delegate: NotesEditorViewControllerDelegate?

	@IBOutlet weak private var textView: UITextView!

	override func viewDidLoad() {
		super.viewDidLoad()
		textView.text = startupNote
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		if PersistedOptions.darkMode {
			textView.backgroundColor = GladysViewController.darkColor
			textView.textColor = UIColor.lightGray
			navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.darkGray]
		}
	}

	@IBAction func saveSelected(_ sender: UIBarButtonItem) {
		let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		delegate?.newNoteSaved(note: text)
		navigationController?.popViewController(animated: true)
	}
}
