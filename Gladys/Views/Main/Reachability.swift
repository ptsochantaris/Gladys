
import Foundation
import SystemConfiguration

let reachability = Reachability()

class Reachability {

	private let reachability: SCNetworkReachability

	init() {
		var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
		zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		zeroAddress.sin_family = sa_family_t(AF_INET)

		reachability = withUnsafePointer(to: &zeroAddress) { pointer in
			let p = UnsafePointer<sockaddr>(OpaquePointer(pointer))
			return SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, p)!
		}

		var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)

		if (SCNetworkReachabilitySetCallback(reachability, { target, flags, info in
			NotificationCenter.default.post(name: .ReachabilityChangedNotification, object: nil)
		}, &context)) {
			if (SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)) {
				log("Reachability monitoring active")
				return
			}
		}
		log("Reachability monitoring start failed")
	}

	enum NetworkStatus: Int {
		case NotReachable, ReachableViaWiFi, ReachableViaWWAN
		static let descriptions = ["Down", "WiFi", "Cellular"]
		var name: String { return NetworkStatus.descriptions[rawValue] }
	}

	deinit {
		SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
	}

	var status: NetworkStatus {

		var flags = SCNetworkReachabilityFlags()
		var returnValue = NetworkStatus.NotReachable

		if SCNetworkReachabilityGetFlags(reachability, &flags) {
			if flags.contains(.reachable) {

				if !flags.contains(.connectionRequired) { returnValue = .ReachableViaWiFi }

				if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
					if !flags.contains(.interventionRequired) { returnValue = .ReachableViaWiFi }
				}

				if flags.contains(.isWWAN) { returnValue = .ReachableViaWWAN }
			}
		}

		return returnValue
	}
}
