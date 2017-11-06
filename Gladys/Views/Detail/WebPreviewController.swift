//
//  WebPreviewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 28/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import WebKit

final class WebPreviewController: GladysViewController, WKNavigationDelegate {
	
	@IBOutlet weak var web: WKWebView!
	@IBOutlet weak var statusLabel: UILabel!

	var address: URL!

	override func viewDidLoad() {
		super.viewDidLoad()

		let r = URLRequest(url: address)
		web.navigationDelegate = self
		web.load(r)
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		statusLabel.text = nil
		statusLabel.isHidden = true
		title = webView.title
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		statusLabel.text = error.finalDescription
		statusLabel.isHidden = false
		title = nil
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		statusLabel.text = error.finalDescription
		statusLabel.isHidden = false
		title = nil
	}

	override var preferredContentSize: CGSize {
		get {
			return UIApplication.shared.windows.first!.bounds.size
		}
		set {}
	}
}
