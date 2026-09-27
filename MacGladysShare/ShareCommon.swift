import AppKit

nonisolated let sharingPasteboard = NSPasteboard.Name("build.bru.MacGladys.SharePasteboard")

nonisolated extension Notification.Name {
    static let SharingPasteboardPasted = Notification.Name("SharingPasteboardPasted")
}
