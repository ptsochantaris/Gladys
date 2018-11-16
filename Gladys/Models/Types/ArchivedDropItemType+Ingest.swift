
import Contacts
import MobileCoreServices
import UIKit

extension UIColor {
	var hexValue: String {
		var redFloatValue:CGFloat = 0.0, greenFloatValue:CGFloat = 0.0, blueFloatValue:CGFloat = 0.0
		getRed(&redFloatValue, green: &greenFloatValue, blue: &blueFloatValue, alpha: nil)
		let r = Int(redFloatValue * 255.99999)
		let g = Int(greenFloatValue * 255.99999)
		let b = Int(blueFloatValue * 255.99999)
		return String(format: "#%02X%02X%02X", r, g, b)
	}
}

extension ArchivedDropItemType {

	func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool) {

		if storeBytes {
			setBytes(data)
		}
		representedClass = .url
		setTitle(from: url)
		
		if url.isFileURL {
			log("      received local file url: \(url.path)")
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
			completeIngest()
		} else {
			handleRemoteUrl(url, data, storeBytes)
		}
	}
}
