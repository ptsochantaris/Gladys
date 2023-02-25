import Foundation
import GladysCommon

@MainActor
public enum SortOption {
    case dateAdded, dateModified, title, note, size, label
    public var ascendingTitle: String {
        switch self {
        case .dateAdded: return "Oldest Item First"
        case .dateModified: return "Oldest Update First"
        case .title: return "Title (A-Z)"
        case .note: return "Note (A-Z)"
        case .label: return "First Label (A-Z)"
        case .size: return "Smallest First"
        }
    }

    public var descendingTitle: String {
        switch self {
        case .dateAdded: return "Newest Item First"
        case .dateModified: return "Newest Update First"
        case .title: return "Title (Z-A)"
        case .note: return "Note (Z-A)"
        case .label: return "First Label (Z-A)"
        case .size: return "Largest First"
        }
    }

    private func sortElements(itemsToSort: ContiguousArray<ArchivedItem>) -> (ContiguousArray<ArchivedItem>, [Int]) {
        var itemIndexes = [Int]()
        let toCheck = itemsToSort.isEmpty ? DropStore.allDrops : itemsToSort
        let actualItemsToSort = toCheck.compactMap { item -> ArchivedItem? in
            if let index = DropStore.indexOfItem(with: item.uuid) {
                itemIndexes.append(index)
                return item
            }
            return nil
        }
        assert(actualItemsToSort.count == itemIndexes.count)
        return (ContiguousArray(actualItemsToSort), itemIndexes.sorted())
    }

    public func handlerForSort(itemsToSort: ContiguousArray<ArchivedItem>, ascending: Bool) -> () -> Void {
        var (actualItemsToSort, itemIndexes) = sortElements(itemsToSort: itemsToSort)
        let sortType = self
        return {
            switch sortType {
            case .dateAdded:
                if ascending {
                    actualItemsToSort.sort { $0.createdAt < $1.createdAt }
                } else {
                    actualItemsToSort.sort { $0.createdAt > $1.createdAt }
                }
            case .dateModified:
                if ascending {
                    actualItemsToSort.sort { $0.updatedAt < $1.updatedAt }
                } else {
                    actualItemsToSort.sort { $0.updatedAt > $1.updatedAt }
                }
            case .title:
                if ascending {
                    actualItemsToSort.sort { $0.displayTitleOrUuid.localizedCaseInsensitiveCompare($1.displayTitleOrUuid) == .orderedAscending }
                } else {
                    actualItemsToSort.sort { $0.displayTitleOrUuid.localizedCaseInsensitiveCompare($1.displayTitleOrUuid) == .orderedDescending }
                }
            case .note:
                if ascending {
                    actualItemsToSort.sort { $0.note.localizedCaseInsensitiveCompare($1.note) == .orderedAscending }
                } else {
                    actualItemsToSort.sort { $0.note.localizedCaseInsensitiveCompare($1.note) == .orderedDescending }
                }
            case .label:
                if ascending {
                    actualItemsToSort.sort {
                        // treat empty as after Z
                        guard let l1 = $0.labels.first else {
                            return false
                        }
                        guard let l2 = $1.labels.first else {
                            return true
                        }
                        return l1.localizedCaseInsensitiveCompare(l2) == .orderedAscending
                    }
                } else {
                    actualItemsToSort.sort {
                        // treat empty as after Z
                        guard let l1 = $0.labels.first else {
                            return false
                        }
                        guard let l2 = $1.labels.first else {
                            return true
                        }
                        return l1.localizedCaseInsensitiveCompare(l2) == .orderedDescending
                    }
                }
            case .size:
                if ascending {
                    actualItemsToSort.sort { $0.sizeInBytes < $1.sizeInBytes }
                } else {
                    actualItemsToSort.sort { $0.sizeInBytes > $1.sizeInBytes }
                }
            }
            for pos in 0 ..< itemIndexes.count {
                let itemIndex = itemIndexes[pos]
                let item = actualItemsToSort[pos]
                DropStore.replace(drop: item, at: itemIndex)
            }
            Task {
                await Model.save()
            }
        }
    }

    public static var options: [SortOption] { [.title, .dateAdded, .dateModified, .note, .label, .size] }
}
