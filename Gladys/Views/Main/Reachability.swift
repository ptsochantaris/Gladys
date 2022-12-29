import Foundation
import SystemConfiguration

let reachability = Reachability()

final actor Reachability {
    private let reachability: SCNetworkReachability

    init() {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        reachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, $0)!
            }
        }

        let changeCallback: SCNetworkReachabilityCallBack = { _, flags, _ in
            let newStatus = Reachability.status(from: flags)
            log("Rechability changed: \(newStatus.name)")
            Task { @MainActor in
                sendNotification(name: .ReachabilityChanged, object: newStatus)
            }
        }

        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        if SCNetworkReachabilitySetCallback(reachability, changeCallback, &context), SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            log("Reachability monitoring active")
        } else {
            log("Reachability monitoring start failed")
        }
    }

    var isReachableViaWiFi: Bool {
        status == .reachableViaWiFi
    }

    var notReachableViaWiFi: Bool {
        status != .reachableViaWiFi
    }
    
    var statusName: String {
        status.name
    }

    private enum NetworkStatus: Int {
        case notReachable, reachableViaWiFi, reachableViaWWAN
        var name: String {
            switch self {
            case .notReachable: return "Down"
            case .reachableViaWiFi: return "WiFi"
            case .reachableViaWWAN: return "Cellular"
            }
        }
    }

    deinit {
        SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private static func status(from flags: SCNetworkReachabilityFlags) -> NetworkStatus {
        var returnValue = NetworkStatus.notReachable
        if flags.contains(.reachable) {
            if !flags.contains(.connectionRequired) { returnValue = .reachableViaWiFi }

            if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
                if !flags.contains(.interventionRequired) { returnValue = .reachableViaWiFi }
            }

            if flags.contains(.isWWAN) { returnValue = .reachableViaWWAN }
        }
        return returnValue
    }

    private var status: NetworkStatus {
        var flags = SCNetworkReachabilityFlags()
        if SCNetworkReachabilityGetFlags(reachability, &flags) {
            return Reachability.status(from: flags)
        } else {
            return .notReachable
        }
    }
}
