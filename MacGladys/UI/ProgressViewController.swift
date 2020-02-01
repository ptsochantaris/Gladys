//
//  ProgressViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 02/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class ProgressViewController: NSViewController {
	@IBOutlet private weak var titleLabel: NSTextField!
	@IBOutlet private weak var progressIndicator: NSProgressIndicator!

	private var monitoredProgress: Progress?
    private var observer: NSKeyValueObservation?

	func startMonitoring(progress: Progress?, titleOverride: String?) {
		monitoredProgress = progress
		if let monitoredProgress = monitoredProgress {
            observer = monitoredProgress.observe(\Progress.completedUnitCount, options: .new) { [weak self] p, _ in
                self?.update(from: p)
            }
			update(from: monitoredProgress)
		} else {
			progressIndicator.isIndeterminate = true
		}
		if let titleOverride = titleOverride {
			titleLabel.stringValue = titleOverride
		}
	}

	func endMonitoring() {
		monitoredProgress?.removeObserver(self, forKeyPath: "completedUnitCount")
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
