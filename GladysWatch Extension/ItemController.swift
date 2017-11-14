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

	override func awake(withContext context: Any?) {
		let c = context as! [String: Any]
		label.setText(c["t"] as? String)
		date.setText(formatter.string(from: c["d"] as? Date ?? .distantPast))

		uuid = c["u"] as? String
		WCSession.default.sendMessage(["image": uuid!], replyHandler: { reply in
			if let r = reply["imagePng"] as? Data {
				DispatchQueue.main.async {
					self.image.setImage(UIImage(data: r))
				}
			}
		}, errorHandler: nil)
	}

	private var copying: Bool = false {
		didSet {
			label.setHidden(copying)
			date.setHidden(copying)
			image.setHidden(copying)
			copyLabel.setHidden(!copying)
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
