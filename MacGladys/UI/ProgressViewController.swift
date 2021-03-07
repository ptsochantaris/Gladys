//
//  ProgressViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 02/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class ProgressViewController: NSViewController {
	@IBOutlet private var titleLabel: NSTextField!
	@IBOutlet private var progressIndicator: NSProgressIndicator!

    private var observer: NSKeyValueObservation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Processing..."
    }

	func startMonitoring(progress: Progress?, titleOverride: String?) {
		if let monitoredProgress = progress {
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
        observer = nil
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
