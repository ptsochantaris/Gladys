import Foundation
import Lista

public extension Sequence where Element: Hashable {
    var uniqued: [Element] {
        var set = Set<Element>()
        set.reserveCapacity(underestimatedCount)
        return filter { set.insert($0).inserted }
    }
}

extension Array: Identifiable where Element: Identifiable {
    public var id: String {
        map { String(describing: $0) }.joined()
    }
}

public extension Collection {
    var isPopulated: Bool {
        !isEmpty
    }
}

public extension Collection where Self.Index == Int {
    func bunch(maxSize: Int) -> [[Element]] {
        var pos = 0
        let slices = Lista<Self.SubSequence>()
        while pos < count {
            let end = Swift.min(count, pos + maxSize)
            slices.append(self[pos ..< end])
            pos += maxSize
        }
        return slices.map { Array($0) }
    }
}
