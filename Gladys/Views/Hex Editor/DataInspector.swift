//
//  DataInspector.swift
//  FEFF
//
//  Created by Paul Tsochantaris on 02/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class DataInspector: GladysViewController {

	static func setBool(_ name: String, _ value: Bool) {
		UserDefaults.standard.set(value, forKey: name)
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

	@IBOutlet private weak var bit16: UILabel!
	@IBOutlet private weak var bit32: UILabel!
	@IBOutlet private weak var bit64: UILabel!

	@IBOutlet private weak var scrollView: UIScrollView!

	@IBOutlet private weak var signedSwitch: UISwitch!
	@IBOutlet private weak var littleEndianSwitch: UISwitch!
	@IBOutlet private weak var decimalSwitch: UISwitch!
	@IBOutlet private weak var decimalLabel: UILabel!
	@IBOutlet private weak var hexadecimalLabel: UILabel!
	@IBOutlet private weak var bigEndian: UILabel!
	@IBOutlet private weak var littleEndian: UILabel!
	@IBOutlet private weak var signedLabel: UILabel!
	@IBOutlet private weak var unsignedLabel: UILabel!

	var signedAccessibility: UIAccessibilityElement!
	var endianAccessibility: UIAccessibilityElement!
	var decimalAccessibility: UIAccessibilityElement!

	override func viewDidLoad() {
		super.viewDidLoad()

		signedSwitch.isOn = DataInspector.signedSwitchOn
		signedSwitch.addTarget(self, action: #selector(switchesChanged), for: .valueChanged)
		signedSwitch.onTintColor = view.tintColor

		littleEndianSwitch.isOn = DataInspector.littleEndianSwitchOn
		littleEndianSwitch.addTarget(self, action: #selector(switchesChanged), for: .valueChanged)
		littleEndianSwitch.onTintColor = view.tintColor

		decimalSwitch.isOn = DataInspector.decimalSwitchOn
		decimalSwitch.addTarget(self, action: #selector(switchesChanged), for: .valueChanged)
		decimalSwitch.onTintColor = view.tintColor

		signedAccessibility = UIAccessibilityElement(accessibilityContainer: view)
		signedAccessibility.accessibilityTraits = .button
		signedAccessibility.accessibilityFrameInContainerSpace = [signedLabel, unsignedLabel].reduce(signedSwitch.frame) { frame, view -> CGRect in
			return frame.union(view.frame)
		}

		endianAccessibility = UIAccessibilityElement(accessibilityContainer: view)
		endianAccessibility.accessibilityTraits = .button
		endianAccessibility.accessibilityFrameInContainerSpace = [littleEndian, bigEndian].reduce(littleEndianSwitch.frame) { frame, view -> CGRect in
			return frame.union(view.frame)
		}

		decimalAccessibility = UIAccessibilityElement(accessibilityContainer: view)
		decimalAccessibility.accessibilityTraits = .button
		decimalAccessibility.accessibilityFrameInContainerSpace = [decimalLabel, hexadecimalLabel].reduce(decimalSwitch.frame) { frame, view -> CGRect in
			return frame.union(view.frame)
		}

		view.accessibilityElements = [bit16, bit32, bit64, signedAccessibility, endianAccessibility, decimalAccessibility]
		switchesChanged()
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		if PersistedOptions.darkMode {
			let b = UIColor.darkGray
			self.popoverPresentationController?.backgroundColor = b
			view.backgroundColor = b
			for v in view.subviews {
				if let v = v as? UILabel {
					v.textColor = .lightGray
				}
			}
			bit16.textColor = .white
			bit32.textColor = .white
			bit64.textColor = .white
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		signedAccessibility.accessibilityActivationPoint = view.convert(signedSwitch.center, to: mainWindow)
		endianAccessibility.accessibilityActivationPoint = view.convert(littleEndianSwitch.center, to: mainWindow)
		decimalAccessibility.accessibilityActivationPoint = view.convert(decimalSwitch.center, to: mainWindow)
	}

	@objc private func updateBytes() {

		if bytes.count == 0 {
			done()
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

		bit16.accessibilityLabel = "16-bit"
		bit16.accessibilityValue = bit16.text
		bit32.accessibilityLabel = "32-bit"
		bit32.accessibilityValue = bit32.text
		bit64.accessibilityLabel = "64-bit"
		bit64.accessibilityValue = bit64.text
	}

	@objc private func switchesChanged() {
		updateBytes()
		signedAccessibility.accessibilityValue = signedSwitch.isOn ? "Un-signed" : "Signed"
		endianAccessibility.accessibilityValue = littleEndianSwitch.isOn ? "Big-endian" : "Little-endian"
		decimalAccessibility.accessibilityValue = decimalSwitch.isOn ? "Hexadecimal" : "Decimal"
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
