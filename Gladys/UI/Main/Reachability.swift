import GladysCommon
import Network

final actor Reachability {
    static let shared = Reachability()

    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let ethernetMonitor = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
    private let cellularMonitor = NWPathMonitor(requiredInterfaceType: .cellular)
    private var lastStatus = "None"

    init() {
        wifiMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.update()
            }
        }

        ethernetMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.update()
            }
        }
        cellularMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.update()
            }
        }
        wifiMonitor.start(queue: .main)
        ethernetMonitor.start(queue: .main)
        cellularMonitor.start(queue: .main)
        log("Reachabillity monitor active")
    }

    private func update() {
        let newName = statusName
        if lastStatus == newName {
            return
        }
        lastStatus = newName
        log("Reachability update: \(newName)")
        Task { @MainActor in
            sendNotification(name: .ReachabilityChanged, object: nil)
        }
    }

    var isReachableViaLowCost: Bool {
        wifiMonitor.currentPath.status == .satisfied || ethernetMonitor.currentPath.status == .satisfied
    }

    var statusName: String {
        if wifiMonitor.currentPath.status == .satisfied {
            "WiFi"
        } else if ethernetMonitor.currentPath.status == .satisfied {
            "Ethernet"
        } else if cellularMonitor.currentPath.status == .satisfied {
            "Cellular"
        } else {
            "None"
        }
    }
}
