import Foundation

extension NSItemProvider {
    func loadDataRepresentation(for typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            _ = self.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(with: .success(data))
                } else {
                    continuation.resume(throwing: error ?? GladysError.noData.error)
                }
            }
        }
    }
}
