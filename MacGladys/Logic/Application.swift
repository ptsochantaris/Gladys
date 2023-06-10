import AppKit

extension NSTextField {
    @objc final func gladysUndo() {
        currentEditor()?.undoManager?.undo()
    }

    @objc final func gladysRedo() {
        currentEditor()?.undoManager?.redo()
    }

    @objc final func gladysCopy() {
        currentEditor()?.copy(nil)
    }

    @objc final func gladysPaste() {
        currentEditor()?.paste(nil)
    }

    @objc final func gladysCut() {
        currentEditor()?.cut(nil)
    }
}

final class Application: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == .command {
                if let char = event.charactersIgnoringModifiers {
                    switch char {
                    case "x": if sendAction(#selector(NSTextField.gladysCut), to: nil, from: self) { return }
                    case "v": if sendAction(#selector(NSTextField.gladysPaste), to: nil, from: self) { return }
                    case "z": if sendAction(#selector(NSTextField.gladysUndo), to: nil, from: self) { return }
                    case "c": if sendAction(#selector(NSTextField.gladysCopy), to: nil, from: self) { return }
                    case "a": if sendAction(#selector(NSResponder.selectAll), to: nil, from: self) { return }
                    default: break
                    }
                }
            } else if modifiers == [.command, .shift] {
                if let char = event.charactersIgnoringModifiers {
                    if char == "Z", sendAction(#selector(NSTextField.gladysRedo), to: nil, from: self) { return }
                }
            }
        }
        super.sendEvent(event)
    }
}
