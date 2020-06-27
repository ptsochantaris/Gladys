//
//  WebPreviewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 28/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MobileCoreServices
import WebKit

final class WebPreviewController: GladysViewController, WKNavigationDelegate {
	
	@IBOutlet private weak var web: WKWebView!
	@IBOutlet private weak var statusLabel: UILabel!
	@IBOutlet private weak var spinner: UIActivityIndicatorView!

	var address: URL?
	var webArchive: Component?

	var relatedItem: ArchivedItem?
	var relatedChildItem: Component?

	private var loadCheck1: NSKeyValueObservation!
	private var loadCheck2: NSKeyValueObservation!

	override func viewDidLoad() {
		super.viewDidLoad()
        
        doneButtonLocation = .right
        windowButtonLocation = .right
        
		loadCheck1 = web.observe(\.estimatedProgress, options: .new) { [weak self] _, v in
			if let s = self, let n = v.newValue, n > 0.85 {
                s.showError(nil)
                s.loadCheck1 = nil
			}
		}

		loadCheck2 = web.observe(\.title, options: .new) { [weak self] _, v in
			assert(Thread.isMainThread)
			if let n = v.newValue {
				self?.title = n
				self?.loadCheck2 = nil
			}
		}

		web.navigationDelegate = self
		if let address = address {
			let r = URLRequest(url: address)
			web.load(r)
		} else if let archiveComponent = webArchive,
            let bytes = archiveComponent.bytes,
            let mimeType = UTTypeCopyPreferredTagWithClass(kUTTypeWebArchive, kUTTagClassMIMEType)?.takeRetainedValue() {
            web.load(bytes, mimeType: mimeType as String, characterEncodingName: "utf-8", baseURL: URL(string: "about:blank")!)
		}

		if relatedItem != nil {
			userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
		}        
	}

	override func updateUserActivityState(_ activity: NSUserActivity) {
		super.updateUserActivityState(activity)
		if let relatedItem = relatedItem {
			ArchivedItem.updateUserActivity(activity, from: relatedItem, child: relatedChildItem, titled: "Web preview of")
		}
	}

	deinit {
		loadCheck1 = nil
		loadCheck2 = nil
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		spinner.stopAnimating()
		statusLabel.text = nil
		statusLabel.isHidden = true
		title = webView.title
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
	}
    
    private func showError(_ error: Error?) {
        spinner.stopAnimating()
        let text = error?.finalDescription
        statusLabel.text = text
        statusLabel.isHidden = text == nil
    }

	override var preferredContentSize: CGSize {
		get {
            let s = mainWindow.bounds.size
            let w = min(s.width, s.height)
            let h = max(s.width, s.height)
            if h / w > 1.4 {
                return CGSize(width: w, height: h / 1.4)
            } else {
                return CGSize(width: w, height: h)
            }
		}
		set {}
	}
}
