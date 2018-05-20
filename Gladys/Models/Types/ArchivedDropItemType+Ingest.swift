
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

	func handleUrl(_ url: URL, _ data: Data) {
		
		bytes = data
		representedClass = .url
		setTitle(from: url)
		
		if url.isFileURL {
			log("      received local file url: \(url.path)")
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
			completeIngest()
		} else {
			log("      received remote url: \(url.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
			if let s = url.scheme, s.hasPrefix("http") {
				fetchWebPreview(for: url) { [weak self] title, image in
					if self?.loadingAborted ?? true { return }
					self?.accessoryTitle = title ?? self?.accessoryTitle
					if let image = image {
						if image.size.height > 100 || image.size.width > 200 {
							self?.setDisplayIcon(image, 30, .fit)
						} else {
							self?.setDisplayIcon(image, 30, .center)
						}
					}
					self?.completeIngest()
				}
			} else {
				completeIngest()
			}
		}
	}
}
