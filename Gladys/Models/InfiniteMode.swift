
#if MAINAPP || ACTIONEXTENSION || INTENTSEXTENSION
import UIKit
import GladysFramework

fileprivate func getDeviceId() -> Data {
	guard let identifier = UIDevice.current.identifierForVendor as NSUUID? else { return Data() }
	var uuidBytes: [UInt8] = [UInt8](repeating: 0, count: 16)
	identifier.getBytes(&uuidBytes)
	return Data(uuidBytes)
}
#endif

#if MAC
import Foundation
import MacGladysFramework

fileprivate func getDeviceId() -> Data {

	var master_port = mach_port_t()
	var kernResult = IOMasterPort(mach_port_t(MACH_PORT_NULL), &master_port)
	if kernResult != KERN_SUCCESS {
		log("IOMasterPort returned \(kernResult)")
		return Data()
	}

	let matchingDict = IOBSDNameMatching(master_port, 0, "en0")
	if matchingDict == nil {
		log("IOBSDNameMatching returned empty dictionary")
		return Data()
	}

	var iterator = io_iterator_t()
	kernResult = IOServiceGetMatchingServices(master_port, matchingDict, &iterator)
	if kernResult != KERN_SUCCESS {
		log("IOServiceGetMatchingServices returned \(kernResult)")
		return Data()
	}

	var macAddress: CFData?

	while true {
		let service = IOIteratorNext(iterator)
		if service == 0 { break }

		var parentService = io_object_t()
		kernResult = IORegistryEntryGetParentEntry(service, kIOServicePlane, &parentService)
		if (kernResult == KERN_SUCCESS) {
			let m = IORegistryEntryCreateCFProperty(parentService, "IOMACAddress" as CFString, kCFAllocatorDefault, 0).takeUnretainedValue()
			macAddress = (m as! CFData)
			IOObjectRelease(parentService)
		} else {
			log("IORegistryEntryGetParentEntry returned \(kernResult)")
		}

		IOObjectRelease(service)
	}
	IOObjectRelease(iterator)

	if let macAddress = macAddress {
		return macAddress as Data
	} else {
		return Data()
	}
}

#if DEBUG
var receiptExists = true
#else
var receiptExists: Bool {
	if let receiptUrl = Bundle.main.appStoreReceiptURL {
		return FileManager.default.fileExists(atPath: receiptUrl.path)
	} else {
		return false
	}
}
#endif
#endif

let nonInfiniteItemLimit = 10

#if DEBUG
var infiniteMode = true
func reVerifyInfiniteMode() {}
#else

var infiniteMode = verifyIapReceipt(getDeviceId())
func reVerifyInfiniteMode() {
	infiniteMode = verifyIapReceipt(getDeviceId())
	#if MAC
	NotificationCenter.default.post(name: .IAPModeChanged, object: nil)
	#endif
}
#endif
