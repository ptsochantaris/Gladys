//
//  PointerStack.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/01/2023.
//  Copyright © 2023 Paul Tsochantaris. All rights reserved.
//

import Foundation

final class PointerStack<Value: AnyObject>: Sequence {
    typealias StorageElement = Unmanaged<Value>
    private var count = 0
    
    private let buffer: UnsafeMutableRawPointer
    private let stride = MemoryLayout<StorageElement>.stride

    init(capacity: Int) {
        let alignment = MemoryLayout<StorageElement>.alignment
        buffer = UnsafeMutableRawPointer.allocate(byteCount: stride * capacity, alignment: alignment)
    }
    
    func append(_ newValue: Value) {
        let ref = Unmanaged.passRetained(newValue)
        buffer.advanced(by: stride * count).storeBytes(of: ref, as: StorageElement.self)
        count += 1
    }
    
    func popLast() -> Value? {
        if count == 0 {
            return nil
        }
        count -= 1
        let v = buffer.load(fromByteOffset: stride * count, as: StorageElement.self)
        return v.autorelease().takeUnretainedValue()
    }
    
    deinit {
        for i in 0 ..< count {
            let v = buffer.load(fromByteOffset: stride * i, as: StorageElement.self)
            v.release()
        }
        buffer.deallocate()
    }

    struct PointerStackIterator: IteratorProtocol {
        private var current = 0
        private let count: Int
        private let stride: Int
        private let buffer: UnsafeMutableRawPointer

        fileprivate init(_ count: Int, _ stride: Int, _ buffer: UnsafeMutableRawPointer) {
            self.count = count
            self.stride = stride
            self.buffer = buffer
        }

        mutating func next() -> Value? {
            if current == count {
                return nil
            }
            let v = buffer.load(fromByteOffset: stride * current, as: StorageElement.self)
            current += 1
            return v.takeUnretainedValue()
        }
    }

    func makeIterator() -> PointerStackIterator {
        PointerStackIterator(count, stride, buffer)
    }
}
