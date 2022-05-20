//
//  NSItemProvider+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 20/05/2022.
//  Copyright © 2022 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension NSItemProvider {
    func loadDataRepresentation(for typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            _ = self.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data = data {
                    continuation.resume(with: .success(data))
                } else {
                    continuation.resume(throwing: error ?? GladysError.noData.error)
                }
            }
        }
    }
}
