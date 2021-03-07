//
//  NoteEditorController.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/12/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class NoteEditorController: UIViewController {

	@IBOutlet private var textView: UITextView!

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
        commitNote()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
        textView.text = ActionRequestViewController.noteToApply
        NotificationCenter.default.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)
        itemIngested(nil)
    }
    
    @objc private func itemIngested(_ notification: Notification?) {
        if Model.doneIngesting {
            navigationItem.rightBarButtonItem = makeDoneButton(target: self, action: #selector(done))
        }
    }
    
    @objc private func done() {
        commitNote()
        NotificationCenter.default.post(name: .DoneSelected, object: nil)
    }
    
    private func commitNote() {
        ActionRequestViewController.noteToApply = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		textView.becomeFirstResponder()
	}
}
