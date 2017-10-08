//
//  DataInspector.swift
//  FEFF
//
//  Created by Paul Tsochantaris on 02/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class DataInspector: UIViewController {

	static func setBool(_ name: String, _ value: Bool) {
		UserDefaults.standard.set(value, forKey: name)
		UserDefaults.standard.synchronize()
	}

	static func getBool(_ name: String) -> Bool {
		return UserDefaults.standard.bool(forKey: name)
	}

	static var signedSwitchOn: Bool {
		get {
			return getBool("Hex-signedSwitchOn")
		}
		set {
			setBool("Hex-signedSwitchOn", newValue)
		}
	}

	static var littleEndianSwitchOn: Bool {
		get {
			return getBool("Hex-littleEndianSwitchOn")
		}
		set {
			setBool("Hex-littleEndianSwitchOn", newValue)
		}
	}

	static var decimalSwitchOn: Bool {
		get {
			return getBool("Hex-decimalSwitchOn")
		}
		set {
			setBool("Hex-decimalSwitchOn", newValue)
		}
	}

	var bytes: [UInt8]! {
		didSet {
			if isViewLoaded {
				updateBytes()
			}
		}
	}

	@IBOutlet weak var bit16: UILabel!
	@IBOutlet weak var bit32: UILabel!
	@IBOutlet weak var bit64: UILabel!

	@IBOutlet weak var scrollView: UIScrollView!

	@IBOutlet weak var signedSwitch: UISwitch!
	@IBOutlet weak var littleEndianSwitch: UISwitch!
	@IBOutlet weak var decimalSwitch: UISwitch!

	override func viewDidLoad() {
		super.viewDidLoad()

		signedSwitch.isOn = DataInspector.signedSwitchOn
		signedSwitch.addTarget(self, action: #selector(updateBytes), for: .valueChanged)
		signedSwitch.onTintColor = view.tintColor

		littleEndianSwitch.isOn = DataInspector.littleEndianSwitchOn
		littleEndianSwitch.addTarget(self, action: #selector(updateBytes), for: .valueChanged)
		littleEndianSwitch.onTintColor = view.tintColor

		decimalSwitch.isOn = DataInspector.decimalSwitchOn
		decimalSwitch.addTarget(self, action: #selector(updateBytes), for: .valueChanged)
		decimalSwitch.onTintColor = view.tintColor

		updateBytes()
	}

	@objc private func updateBytes() {

		if bytes.count == 0 {
			doneSelected(nil)
			return
		}

		if bytes.count > 2 {
			bit16.text = "Select Less"
			bit16.alpha = 0.3
		} else {
            bit16.text = signedSwitch.isOn ? calculate(UInt16.self) : calculate(Int16.self)
			bit16.alpha = 1
		}

		if bytes.count > 4 {
			bit32.text = "Select Less"
			bit32.alpha = 0.3
		} else {
            bit32.text = signedSwitch.isOn ? calculate(UInt32.self) : calculate(Int32.self)
			bit32.alpha = 1
		}

		if bytes.count > 8 {
			bit64.text = "Select Less"
			bit64.alpha = 0.3
		} else {
            bit64.text = signedSwitch.isOn ? calculate(UInt64.self) : calculate(Int64.self)
			bit64.alpha = 1
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		scrollView.layoutIfNeeded()
		preferredContentSize = scrollView.contentSize
	}

	private func resultToText<T: FixedWidthInteger>(resultType: T.Type, buffer: [UInt8]) -> String {

		let value = UnsafePointer(buffer)!.withMemoryRebound(to: resultType, capacity: 1) { $0.pointee }
        
		if decimalSwitch.isOn {
            return String(format: "0x%llX", value as! CVarArg)
		} else {
			return "\(value)"
		}
	}
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DataInspector.signedSwitchOn = signedSwitch.isOn
        DataInspector.decimalSwitchOn = decimalSwitch.isOn
        DataInspector.littleEndianSwitchOn = littleEndianSwitch.isOn
    }
    
    func doneSelected(_ sender: UIBarButtonItem?) {
        if let p = popoverPresentationController, let shouldDismiss = p.delegate?.popoverPresentationControllerShouldDismissPopover {
            if shouldDismiss(p) {
                dismiss(animated: true)
            }
        }
    }
    
    private func calculate<T: FixedWidthInteger>(_ type: T.Type) -> String {
        let byteCount = type.bitWidth / 8
		let maxLength = min(byteCount, bytes.count)
		var buffer = Array(bytes[..<maxLength])
		if littleEndianSwitch.isOn {
            buffer.reverse()
		}
        while buffer.count < byteCount {
            buffer.append(0)
        }

        return resultToText(resultType: type, buffer: buffer)
	}
}
