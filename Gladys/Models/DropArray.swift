//
//  DropArray.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import Foundation

final class DropArray {
    
    private var uuidindex: [UUID: Int]?
    
    var all: ContiguousArray<ArchivedItem>
            
    var isEmpty: Bool {
        return all.isEmpty
    }
    
    var count: Int {
        return all.count
    }
    
    func append(_ newElement: ArchivedItem) {
        uuidindex = nil
        all.append(newElement)
    }
    
    func replaceItem(at index: Int, with item: ArchivedItem) {
        uuidindex = nil
        all[index] = item
    }
    
    private func rebuildIndexIfNeeded() {
        if uuidindex == nil {
            var count = -1
            uuidindex = Dictionary(uniqueKeysWithValues: all.map { count += 1; return ($0.uuid, count) })
            log("Rebuilt drop index")
        }
    }
    
    func firstIndexOfItem(with uuid: UUID) -> Int? {
        rebuildIndexIfNeeded()
        return uuidindex?[uuid]
    }

    func firstItem(with uuid: UUID) -> ArchivedItem? {
        if let i = firstIndexOfItem(with: uuid) {
            return all[i]
        }
        return nil
    }
    
    func firstIndexOfItem(with uuid: String) -> Int? {
        if let uuidData = UUID(uuidString: uuid) {
            return firstIndexOfItem(with: uuidData)
        }
        return nil
    }
    
    func contains(uuid: UUID) -> Bool {
        rebuildIndexIfNeeded()
        return uuidindex?[uuid] != nil
    }

    func sort(by areInIncreasingOrder: (ArchivedItem, ArchivedItem) throws -> Bool) rethrows {
        uuidindex = nil
        try all.sort(by: areInIncreasingOrder)
    }
    
    func append<S>(contentsOf newElements: S) where ArchivedItem == S.Element, S: Sequence {
        uuidindex = nil
        all.append(contentsOf: newElements)
    }

    func insert<S>(contentsOf newElements: S, at index: Int) where ArchivedItem == S.Element, S: Collection {
        uuidindex = nil
        all.insert(contentsOf: newElements, at: index)
    }

    @discardableResult
    func remove(at index: Int) -> ArchivedItem {
        uuidindex = nil
        return all.remove(at: index)
    }

    func insert(_ newElement: ArchivedItem, at i: Int) {
        uuidindex = nil
        all.insert(newElement, at: i)
    }
    
    init() {
        all = ContiguousArray<ArchivedItem>()
    }
    
    init(existingItems: ContiguousArray<ArchivedItem>) {
        all = existingItems
    }
    
    func removeAll(keepingCapacity: Bool) {
        uuidindex = nil
        all.removeAll(keepingCapacity: keepingCapacity)
    }
    
    func removeAll(where shouldBeRemoved: (ArchivedItem) throws -> Bool) rethrows {
        uuidindex = nil
        try all.removeAll(where: shouldBeRemoved)
    }
        
    func clearCaches() {
        for drop in all {
            for component in drop.components {
                component.clearCachedFields()
            }
        }
    }
}
