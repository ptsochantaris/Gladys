import Foundation
import Lista

public extension Collection where Element: Hashable {
    var uniqued: [Element] {
        var set = Set<Element>()
        set.reserveCapacity(underestimatedCount)
        return filter { set.insert($0).inserted }
    }

    func asyncMap<T>(block: (Element) async -> T) async -> [T] {
        var result = [T]()
        result.reserveCapacity(count)
        for element in self {
            await result.append(block(element))
        }
        return result
    }

    func asyncCompactMap<T>(block: (Element) async -> T?) async -> [T] {
        var result = [T]()
        result.reserveCapacity(count)
        for element in self {
            if let converted = await block(element) {
                result.append(converted)
            }
        }
        return result
    }

    func asyncFilter(block: (Element) async -> Bool) async -> [Element] {
        var result = [Element]()
        result.reserveCapacity(count)
        for element in self where await block(element) {
            result.append(element)
        }
        return result
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
