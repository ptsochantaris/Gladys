//
//  NoteEditorController.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/12/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class NoteEditorController: UIViewController {
	var completion: ((String) -> Void)?

	@IBOutlet private weak var textView: UITextView!

	var initialNote = ""

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		completion?(textView.text.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		textView.text = initialNote
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		textView.becomeFirstResponder()
	}
}
