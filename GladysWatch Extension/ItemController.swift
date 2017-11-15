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

class ItemController: WKInterfaceController {
	@IBOutlet var label: WKInterfaceLabel!
	@IBOutlet var date: WKInterfaceLabel!
	@IBOutlet var image: WKInterfaceImage!
	@IBOutlet var copyLabel: WKInterfaceLabel!

	private var uuid: String?
	private var fetchingImage = false
	private var gotImage = false

	override func awake(withContext context: Any?) {
		let c = context as! [String: Any]
		label.setText(c["t"] as? String)
		date.setText(formatter.string(from: c["d"] as? Date ?? .distantPast))

		uuid = c["u"] as? String
		fetchImage()
	}

	private var active = false

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

	private static let imageCache = NSCache<NSString, UIImage>()

	private func fetchImage() {

		guard let uuid = uuid else { return }

		if let i = ItemController.imageCache.object(forKey: uuid as NSString) {
			image.setImage(i)
			fetchingImage = false
			gotImage = true
			return
		}

		fetchingImage = true
		WCSession.default.sendMessage(["image": uuid], replyHandler: { reply in
			if let r = reply["imagePng"] as? Data {
				DispatchQueue.main.async {
					let i = UIImage(data: r)
					if let i = i {
						ItemController.imageCache.setObject(i, forKey: uuid as NSString)
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
			label.setHidden(copying)
			date.setHidden(copying)
			image.setHidden(copying)
			copyLabel.setText("Copying")
			copyLabel.setHidden(!copying)
		}
	}

	private var opening: Bool = false {
		didSet {
			label.setHidden(copying)
			date.setHidden(copying)
			image.setHidden(copying)
			copyLabel.setText("Viewing on Phone")
			copyLabel.setHidden(!copying)
		}
	}

	private var complicating: Bool = false {
		didSet {
			label.setHidden(complicating)
			date.setHidden(complicating)
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
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			complicating = false
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
}
