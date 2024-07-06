import AppIntents
import Foundation

struct GladysShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GladysAppIntents.CopyItem(),
                    phrases: ["Copy \(.applicationName) item to clipboard"],
                    shortTitle: "Copy to clipboard",
                    systemImageName: "doc.on.doc")

        AppShortcut(intent: GladysAppIntents.PasteIntoGladys(),
                    phrases: ["Paste clipboard into \(.applicationName)"],
                    shortTitle: "Paste from clipboard",
                    systemImageName: "arrow.down.doc")

        AppShortcut(intent: GladysAppIntents.OpenGladys(),
                    phrases: ["Select \(.applicationName) item"],
                    shortTitle: "Select item",
                    systemImageName: "square.grid.3x3.topleft.filled")

        AppShortcut(intent: GladysAppIntents.CreateItemFromText(),
                    phrases: ["Create \(.applicationName) item from text"],
                    shortTitle: "Create from text",
                    systemImageName: "doc.text")

        AppShortcut(intent: GladysAppIntents.CreateItemFromText(),
                    phrases: ["Create \(.applicationName) item from link"],
                    shortTitle: "Create from link",
                    systemImageName: "link")

        AppShortcut(intent: GladysAppIntents.CreateItemFromFile(),
                    phrases: ["Create \(.applicationName) item from file"],
                    shortTitle: "Create from file",
                    systemImageName: "doc")

        AppShortcut(intent: GladysAppIntents.DeleteItem(),
                    phrases: ["Delete \(.applicationName) item"],
                    shortTitle: "Delete item",
                    systemImageName: "xmark.bin")
    }
}
