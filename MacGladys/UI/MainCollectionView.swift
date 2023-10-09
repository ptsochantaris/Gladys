import AppKit
import GladysCommon

final class MainCollectionView: NSCollectionView, NSServicesMenuRequestor {
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            window?.gladysController?.toggleQuickLookPreviewPanel(self)
        } else {
            super.keyDown(with: event)
        }
    }

    var actionableSelectedItems: [ArchivedItem] {
        selectionIndexPaths.compactMap {
            if let item = window?.gladysController?.filter.filteredDrops[$0.item] {
                item.flags.contains(.needsUnlock) ? nil : item
            } else {
                nil
            }
        }
    }

    private var selectedTypes = Set<NSPasteboard.PasteboardType>()

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if returnType == nil, let s = sendType, selectedTypes.contains(s) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func updateServices() {
        var sendTypes = Set<NSPasteboard.PasteboardType>()

        for item in actionableSelectedItems {
            for t in item.components.map({ NSPasteboard.PasteboardType($0.typeIdentifier) }) {
                sendTypes.insert(t)
            }
        }
        selectedTypes = sendTypes
        NSApplication.shared.registerServicesMenuSendTypes(Array(sendTypes), returnTypes: [])
    }

    func readSelection(from _: NSPasteboard) -> Bool {
        false
    }

    func writeSelection(to pboard: NSPasteboard, types _: [NSPasteboard.PasteboardType]) -> Bool {
        let objectsToWrite = actionableSelectedItems.compactMap { $0.pasteboardItem(forDrag: false) }
        if objectsToWrite.isEmpty {
            return false
        } else {
            pboard.writeObjects(objectsToWrite)
            return true
        }
    }

    override func selectItems(at indexPaths: Set<IndexPath>, scrollPosition: NSCollectionView.ScrollPosition) {
        super.selectItems(at: indexPaths, scrollPosition: scrollPosition)
        updateServices()
    }
}
