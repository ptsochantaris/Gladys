import Foundation

enum GladysAppIntentsError: Error, CustomLocalizedStringResourceConvertible {
    case noItemsCreated
    case itemNotFound
    case nothingInClipboard

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noItemsCreated: "No items were created from this data"
        case .itemNotFound: "Item could not be found"
        case .nothingInClipboard: "There was nothing in the clipboard"
        }
    }
}
