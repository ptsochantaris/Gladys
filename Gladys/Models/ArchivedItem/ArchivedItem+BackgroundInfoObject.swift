import Foundation

extension ArchivedItem {
    var backgroundInfoObject: Any? {
        var currentItem: Any?
        var currentPriority = -1
        for item in components {
            let (newItem, newPriority) = item.backgroundInfoObject
            if let newItem, newPriority > currentPriority {
                currentItem = newItem
                currentPriority = newPriority
            }
        }
        return currentItem
    }
}
