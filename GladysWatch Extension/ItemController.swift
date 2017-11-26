//
//  ItemController.swift
//  GladysWatch Extension
//
//  Created by Paul Tsochantaris on 14/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import WatchKit
import WatchConnectivity

private let formatter: DateFormatter = {
	let d = DateFormatter()
	d.dateStyle = .medium
	d.timeStyle = .medium
	d.doesRelativeDateFormatting = true
	return d
}()

extension Notification.Name {
	static let GroupsUpdated = Notification.Name("GroupsUpdated")
}

class ItemController: WKInterfaceController {
	@IBOutlet var label: WKInterfaceLabel!
	@IBOutlet var date: WKInterfaceLabel!
	@IBOutlet var image: WKInterfaceImage!
	@IBOutlet var copyLabel: WKInterfaceLabel!
	@IBOutlet var topGroup: WKInterfaceGroup!
	@IBOutlet var bottomGroup: WKInterfaceGroup!

	private var fetchingImage = false
	private var gotImage = false
	private var context: [String: Any]!
	private var active = false

	override func awake(withContext context: Any?) {
		self.context = context as! [String: Any]

		self.setTitle(self.context["it"] as? String)

		fetchImage()
		label.setText(labelText)
		date.setText(formatter.string(from: itemDate))

		topGroup.setBackgroundImage(ItemController.topShade)
		bottomGroup.setBackgroundImage(ItemController.bottomShade)

		NotificationCenter.default.addObserver(forName: .GroupsUpdated, object: nil, queue: OperationQueue.main) { [weak self] n in
			self?.updateGroups()
		}
		updateGroups()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private var labelText: String? {
		return context["t"] as? String
	}

	private var uuid: String? {
		return context["u"] as? String
	}

	private var itemDate: Date {
		return context["d"] as? Date ?? .distantPast
	}

	override func willActivate() {
		super.willActivate()

		if active || ExtensionDelegate.currentUUID.isEmpty, let uuid = uuid {
			ExtensionDelegate.currentUUID = uuid
		}

		active = true

		if !gotImage && !fetchingImage {
			fetchImage()
		}
	}

	override func willDisappear() {
		super.willDisappear()
		ExtensionDelegate.currentUUID = ""
	}

	private static let imageCache = NSCache<NSString, UIImage>()

	private static let topShade = makeGradient(up: false)

	private static let bottomShade = makeGradient(up: true)

	private static func makeGradient(up: Bool) -> UIImage {

		let context = CGContext(data: nil,
								width: 1,
								height: 255,
								bitsPerComponent: 8,
								bytesPerRow: 4,
								space: CGColorSpaceCreateDeviceRGB(),
								bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!

		let components: [CGFloat] = [0.0, 0.0, 0.0, 0.0,
									 0.0, 0.0, 0.0, 0.4,
									 0.0, 0.0, 0.0, 0.5]
		let locations: [CGFloat] = [0.0, 0.9, 1.0]
		let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: components, locations: locations, count: 3)!
		context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: up ? 0 : 255), end: CGPoint(x: 0, y: up ? 255 : 0), options: [])
		return UIImage(cgImage: context.makeImage()!)
	}

	private func fetchImage() {

		guard let uuid = uuid else { return }

		let cacheKey = uuid + String(itemDate.timeIntervalSinceReferenceDate)
		if let i = ItemController.imageCache.object(forKey: cacheKey as NSString) {
			image.setImage(i)
			fetchingImage = false
			gotImage = true
			return
		}

		fetchingImage = true
		var size = contentFrame.size
		size.width *= 2
		size.height *= 2
		WCSession.default.sendMessage(["image": uuid, "width": size.width, "height": size.height], replyHandler: { reply in
			if let r = reply["image"] as? Data {
				DispatchQueue.main.async {
					let i = UIImage(data: r)
					if let i = i {
						ItemController.imageCache.setObject(i, forKey: cacheKey as NSString)
					}
					self.image.setImage(i)
					self.fetchingImage = false
					self.gotImage = true
				}
			}
		}, errorHandler: { error in
			DispatchQueue.main.async {
				self.fetchingImage = false
				self.gotImage = false
			}
		})
	}

	private var copying: Bool = false {
		didSet {
			topGroup.setHidden(copying || ItemController.hidden)
			bottomGroup.setHidden(copying || ItemController.hidden)
			image.setHidden(copying)
			copyLabel.setText("Copying")
			copyLabel.setHidden(!copying)
		}
	}

	private var opening: Bool = false {
		didSet {
			topGroup.setHidden(opening || ItemController.hidden)
			bottomGroup.setHidden(opening || ItemController.hidden)
			image.setHidden(opening)
			copyLabel.setText("Viewing on Phone")
			copyLabel.setHidden(!opening)
		}
	}

	private var complicating: Bool = false {
		didSet {
			topGroup.setHidden(complicating || ItemController.hidden)
			bottomGroup.setHidden(complicating || ItemController.hidden)
			image.setHidden(complicating)
			copyLabel.setText("Setting as Watch face complication text")
			copyLabel.setHidden(!complicating)
		}
	}

	@IBAction func viewOnDeviceSelected() {
		opening = true
		if let uuid = uuid {
			WCSession.default.sendMessage(["view": uuid], replyHandler: { _ in
				self.opening = false
			}, errorHandler: { _ in
				self.opening = false
			})
		}
	}

	@IBAction func complicationSelected() {
		complicating = true
		PersistedOptions.watchComplicationText = labelText ?? ""
		let server = CLKComplicationServer.sharedInstance()
		for a in server.activeComplications ?? [] {
			server.reloadTimeline(for: a)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
			self.complicating = false
		}
	}

	@IBAction func copySelected() {
		copying = true
		if let uuid = uuid {
			WCSession.default.sendMessage(["copy": uuid], replyHandler: { _ in
				self.copying = false
			}, errorHandler: { _ in
				self.copying = false
			})
		}
	}

	private static var hidden = false
	@IBAction func tapped() {
		ItemController.hidden = !ItemController.hidden
		NotificationCenter.default.post(name: .GroupsUpdated, object: nil)
	}

	private func updateGroups() {
		topGroup.setHidden(ItemController.hidden)
		bottomGroup.setHidden(ItemController.hidden)
	}
}
