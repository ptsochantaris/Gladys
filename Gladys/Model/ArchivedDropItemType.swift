
import UIKit
import MapKit

final class ArchivedDropItemType {

	let typeIdentifier: String
	var classType: ClassType?

	private var bytes: Data?
	private let folderUrl: URL
	private let uuid = UUID()

	private weak var delegate: LoadCompletionDelegate?
	private var loadCount = 0
	private var allLoadedWell = true

	func setBytes(object: Any, classType: ClassType) {
		let d = NSMutableData()
		let k = NSKeyedArchiver(forWritingWith: d)
		k.encode(object, forKey: classType.rawValue)
		k.finishEncoding()
		self.bytes = d as Data
		self.classType = classType
	}

	enum ClassType: String {
		case NSString, NSAttributedString, UIColor, UIImage, NSData, MKMapItem, NSURL
	}

	init(provider: NSItemProvider, typeIdentifier: String, parentUrl: URL, delegate: LoadCompletionDelegate) {
		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.folderUrl = parentUrl.appendingPathComponent(uuid.uuidString)

		provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
			if let item = item {
				let receivedTypeString = type(of: item)
				NSLog("name: [\(provider.suggestedName ?? "")] type: [\(typeIdentifier)] class: [\(receivedTypeString)]")
			}

			if let item = item as? NSString {
				NSLog("      received string: \(item)")
				self.setBytes(object: item, classType: .NSString)
				self.signalDone()

			} else if let item = item as? NSAttributedString {
				NSLog("      received attributed string: \(item)")
				self.setBytes(object: item, classType: .NSAttributedString)
				self.signalDone()

			} else if let item = item as? UIColor {
				NSLog("      received color: \(item)")
				self.setBytes(object: item, classType: .UIColor)
				self.signalDone()

			} else if let item = item as? UIImage {
				NSLog("      received image: \(item)")
				self.setBytes(object: item, classType: .UIImage)
				self.signalDone()

			} else if let item = item as? Data {
				NSLog("      received data: \(item)")
				self.classType = .NSData
				self.bytes = item
				self.signalDone()

			} else if let item = item as? MKMapItem {
				NSLog("      received map item: \(item)")
				self.setBytes(object: item, classType: .MKMapItem)
				self.signalDone()

			} else if let item = item as? URL {
				if item.scheme == "file" {
					NSLog("      will duplicate item at local url: \(item)")
					provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isLocal, error in
						if let url = url {
							NSLog("      received local url: \(url)")
							let localUrl = self.copyLocal(url)
							self.setBytes(object: localUrl, classType: .NSURL)
							self.signalDone()

						} else if let error = error {
							NSLog("Error fetching local url file representation: \(error.localizedDescription)")
							self.allLoadedWell = false
							self.signalDone()
						}
					}
				} else {
					NSLog("      received remote url: \(item)")
					self.setBytes(object: item, classType: .NSURL)
					self.signalDone()
				}

			} else if let error = error {
				NSLog("      error receiving item: \(error.localizedDescription)")
				self.allLoadedWell = false
				self.signalDone()


			} else {
				NSLog("      unknown class")
				self.allLoadedWell = false
				self.signalDone()
				// TODO: generate analyitics report to record what type was received and what UTI
			}
		}
	}

	private func signalDone() {
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(success: self.allLoadedWell)
		}
	}

	private func copyLocal(_ url: URL) -> URL {
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
		try! f.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		try! f.copyItem(at: url, to: newUrl)
		return newUrl
	}

	lazy var loadHandler: NSItemProvider.LoadHandler = { completion, requestedClassType, options in

		if let data = self.bytes, let classType = self.classType {

			if requestedClassType != nil {
				let requestedClassName = NSStringFromClass(requestedClassType)
				if requestedClassName == "NSData" {
					completion(data as NSData, nil)
					return
				}
			}

			let u = NSKeyedUnarchiver(forReadingWith: data)
			let item = u.decodeObject(of: [NSClassFromString(classType.rawValue)!], forKey: classType.rawValue) as? NSSecureCoding
			let finalName = String(describing: item)
			NSLog("Responding with \(finalName)")
			completion(item ?? (data as NSData), nil)

		} else {
			completion(nil, nil)
		}
	}

	var displayIcon: (UIImage?, Int, UIViewContentMode) {
		if let data = self.bytes {
			if classType == .UIImage {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				if let a = u.decodeObject(of: [UIImage.self], forKey: ClassType.UIImage.rawValue) as? UIImage {
					return (a, 15, .scaleAspectFill)
				}
			}

			if typeIdentifier == "public.png" || typeIdentifier == "public.jpeg" {
				if classType == .NSURL {
					let u = NSKeyedUnarchiver(forReadingWith: data)
					if let url = u.decodeObject(of: [NSURL.self], forKey: ClassType.NSURL.rawValue) as? NSURL, let path = url.path, let image = UIImage(contentsOfFile: path) {
						return (image, 10, .scaleAspectFill)
					}
				} else if classType == .NSData {
					if let image = UIImage(data: data) {
						return (image, 10, .scaleAspectFill)
					}
				}
			}

			if typeIdentifier == "public.vcard" {
				return (#imageLiteral(resourceName: "iconPerson"), 5, .center)
			}

			if typeIdentifier == "com.apple.mapkit.map-item" {
				return (#imageLiteral(resourceName: "iconMap"), 5, .center)
			}

			if classType == .NSString || classType == .NSAttributedString || typeIdentifier.hasSuffix("-plain-text") {
				return (#imageLiteral(resourceName: "iconText"), 5, .center)
			}

			if classType == .NSURL {
				if typeIdentifier == "com.apple.DocumentManager.uti.FPItem.File" {
					return (#imageLiteral(resourceName: "iconBlock"), 5, .center)
				} else if typeIdentifier == "com.apple.DocumentManager.uti.FPItem.Location" {
					return(#imageLiteral(resourceName: "iconFolder"), 5, .center)
				} else {
					return(#imageLiteral(resourceName: "iconLink"), 5, .center)
				}
			}
		}
		return (#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
	}

	var displayTitle: (String?, Int) {
		if let data = self.bytes {
			if classType == .NSString {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				if let res = u.decodeObject(of: [NSString.self], forKey: ClassType.NSString.rawValue) as? String {
					return (res, 10)
				}
			} else if classType == .NSAttributedString {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				let a = u.decodeObject(of: [NSAttributedString.self], forKey: ClassType.NSAttributedString.rawValue) as? NSAttributedString
				if let res = a?.string {
					return (res, 7)
				}
			} else if classType == .NSURL {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				let a = u.decodeObject(of: [NSURL.self], forKey: ClassType.NSURL.rawValue) as? NSURL
				if let res = a?.absoluteString {
					return (res, 6)
				}
			} else if typeIdentifier == "public.utf8-plain-text" {
				return (String(data: data, encoding: .utf8), 9)
			} else if typeIdentifier == "public.utf16-plain-text" {
				return (String(data: data, encoding: .utf16), 8)
			}
		}
		return (nil, 0)
	}
}

