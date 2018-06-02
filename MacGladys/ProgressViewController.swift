//
//  ProgressViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 02/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class ProgressViewController: NSViewController {
	@IBOutlet weak var titleLabel: NSTextField!
	@IBOutlet weak var progressIndicator: NSProgressIndicator!

	private var monitoredProgress: Progress?

	func startMonitoring(progress: Progress) {
		monitoredProgress = progress
		monitoredProgress!.addObserver(self, forKeyPath: "completedUnitCount", options: .new, context: nil)
		update(from: monitoredProgress!)
	}

	func endMonitoring() {
		monitoredProgress?.removeObserver(self, forKeyPath: "completedUnitCount")
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		if let p = object as? Progress, p === monitoredProgress {
			update(from: p)
		}
	}

	private func update(from p: Progress) {
		let current = p.completedUnitCount
		let total = p.totalUnitCount
		let progress = (Double(current) * 1000.0) / Double(total)
		DispatchQueue.main.async {
			self.progressIndicator.doubleValue = progress
			self.titleLabel.stringValue = "Completed \(current) of \(total) items"
		}
	}
}
