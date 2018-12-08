//
//  NotesEditor.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 07/12/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class NotesEditor: NSViewController {

	var uuids = [UUID]()

	@IBOutlet private weak var topLabel: NSTextField!
	@IBOutlet private weak var noteField: NSTextField!
	@IBOutlet private weak var saveButton: NSButton!

	override func viewDidLoad() {
		super.viewDidLoad()

		if let commonNote = commonNote {
			noteField.stringValue = commonNote
			if commonNote.isEmpty {
				topLabel.stringValue = "Create a note for the selected items."
				saveButton.title = "Create"
			} else {
				topLabel.stringValue = "Edit the note on the selected items."
				saveButton.title = "Save"
			}
		} else {
			topLabel.stringValue = "The currently selected items have different notes, this will overwrite them."
			noteField.stringValue = ""
			saveButton.title = "Overwrite"
		}
	}

	@IBAction private func cancelSelected(_ sender: NSButton) {
		dismiss(nil)
	}

	@IBAction private func saveSelected(_ sender: NSButton) {
		var changes = false
		let newText = noteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		for uuid in uuids {
			if let item = Model.item(uuid: uuid) {
				if item.note != newText {
					item.note = newText
					changes = true
				}
			}
		}
		if changes {
			ViewController.shared.itemView.reloadData()
			Model.save()
		}
		dismiss(nil)
	}

	private var commonNote: String? {
		if let firstItemUuid = uuids.first {
			let firstItem = Model.item(uuid: firstItemUuid)
			let commonNote = firstItem?.note
			for item in uuids where Model.item(uuid: item)?.note != commonNote {
				return nil
			}
			return commonNote
		}
		return nil
	}
}
