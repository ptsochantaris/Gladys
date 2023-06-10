import AppKit

let sharingPasteboard = NSPasteboard.Name("build.bru.MacGladys.SharePasteboard")

extension Notification.Name {
    static let SharingPasteboardPasted = Notification.Name("SharingPasteboardPasted")
}
