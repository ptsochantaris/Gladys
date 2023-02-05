import Foundation
import GladysCommon

extension Component {
    static var droppedIds = Set<UUID>()

    func register(with provider: NSItemProvider) {
        let t = typeIdentifier
        provider.registerDataRepresentation(forTypeIdentifier: t, visibility: .all) { completion -> Progress? in
            let p = Progress(totalUnitCount: 1)
            Task { @MainActor in
                log("Responding with data block for type: \(t)")
                let response = self.dataForDropping ?? self.bytes
                Component.droppedIds.insert(self.parentUuid)
                p.completedUnitCount = 1
                completion(response, nil)
            }
            return p
        }
    }
}
