import Cocoa

final class NotesEditor: NSViewController {
    var uuids = [UUID]()

    @IBOutlet private var topLabel: NSTextField!
    @IBOutlet private var noteField: NSTextField!
    @IBOutlet private var saveButton: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let commonNote {
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

    @IBAction private func saveSelected(_: NSButton) {
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
