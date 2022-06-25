import UIKit

final class DataInspector: GladysViewController {
    static func setBool(_ name: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: name)
    }

    static func getBool(_ name: String) -> Bool {
        UserDefaults.standard.bool(forKey: name)
    }

    private static var signedSwitchOn: Bool {
        get {
            getBool("Hex-signedSwitchOn")
        }
        set {
            setBool("Hex-signedSwitchOn", newValue)
        }
    }

    private static var littleEndianSwitchOn: Bool {
        get {
            getBool("Hex-littleEndianSwitchOn")
        }
        set {
            setBool("Hex-littleEndianSwitchOn", newValue)
        }
    }

    private static var decimalSwitchOn: Bool {
        get {
            getBool("Hex-decimalSwitchOn")
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

    @IBOutlet private var mainStack: UIStackView!

    @IBOutlet private var bit16: UILabel!
    @IBOutlet private var bit32: UILabel!
    @IBOutlet private var bit64: UILabel!

    @IBOutlet private var signedSwitch: UISegmentedControl!
    @IBOutlet private var littleEndianSwitch: UISegmentedControl!
    @IBOutlet private var decimalSwitch: UISegmentedControl!

    private var signedAccessibility: UIAccessibilityElement!
    private var endianAccessibility: UIAccessibilityElement!
    private var decimalAccessibility: UIAccessibilityElement!

    override func viewDidLoad() {
        super.viewDidLoad()

        signedSwitch.selectedSegmentIndex = DataInspector.signedSwitchOn ? 1 : 0
        signedSwitch.addTarget(self, action: #selector(switchesChanged), for: .valueChanged)

        littleEndianSwitch.selectedSegmentIndex = DataInspector.littleEndianSwitchOn ? 1 : 0
        littleEndianSwitch.addTarget(self, action: #selector(switchesChanged), for: .valueChanged)

        decimalSwitch.selectedSegmentIndex = DataInspector.decimalSwitchOn ? 1 : 0
        decimalSwitch.addTarget(self, action: #selector(switchesChanged), for: .valueChanged)

        signedAccessibility = UIAccessibilityElement(accessibilityContainer: view!)
        signedAccessibility.accessibilityTraits = .button
        signedAccessibility.accessibilityFrameInContainerSpace = signedSwitch.frame

        endianAccessibility = UIAccessibilityElement(accessibilityContainer: view!)
        endianAccessibility.accessibilityTraits = .button
        endianAccessibility.accessibilityFrameInContainerSpace = littleEndianSwitch.frame

        decimalAccessibility = UIAccessibilityElement(accessibilityContainer: view!)
        decimalAccessibility.accessibilityTraits = .button
        decimalAccessibility.accessibilityFrameInContainerSpace = decimalSwitch.frame

        view.accessibilityElements = [bit16!, bit32!, bit64!, signedAccessibility!, endianAccessibility!, decimalAccessibility!]
        switchesChanged()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let currentWindow = currentWindow else { return }
        signedAccessibility.accessibilityActivationPoint = view.convert(signedSwitch.center, to: currentWindow)
        endianAccessibility.accessibilityActivationPoint = view.convert(littleEndianSwitch.center, to: currentWindow)
        decimalAccessibility.accessibilityActivationPoint = view.convert(decimalSwitch.center, to: currentWindow)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        var s = mainStack.systemLayoutSizeFitting(.zero, withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
        s.width += 40
        s.height += 40
        preferredContentSize = s
    }

    @objc private func updateBytes() {
        if bytes.isEmpty {
            done()
            return
        }

        if bytes.count > 2 {
            bit16.text = "Select Less"
            bit16.alpha = 0.3
        } else {
            bit16.text = signedSwitch.selectedSegmentIndex == 1 ? calculate(UInt16.self) : calculate(Int16.self)
            bit16.alpha = 1
        }

        if bytes.count > 4 {
            bit32.text = "Select Less"
            bit32.alpha = 0.3
        } else {
            bit32.text = signedSwitch.selectedSegmentIndex == 1 ? calculate(UInt32.self) : calculate(Int32.self)
            bit32.alpha = 1
        }

        if bytes.count > 8 {
            bit64.text = "Select Less"
            bit64.alpha = 0.3
        } else {
            bit64.text = signedSwitch.selectedSegmentIndex == 1 ? calculate(UInt64.self) : calculate(Int64.self)
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
        signedAccessibility.accessibilityValue = signedSwitch.selectedSegmentIndex == 1 ? "Un-signed" : "Signed"
        endianAccessibility.accessibilityValue = littleEndianSwitch.selectedSegmentIndex == 1 ? "Big-endian" : "Little-endian"
        decimalAccessibility.accessibilityValue = decimalSwitch.selectedSegmentIndex == 1 ? "Hexadecimal" : "Decimal"
    }

    private func resultToText<T: FixedWidthInteger>(resultType: T.Type, buffer: [UInt8]) -> String {
        let value = buffer.withUnsafeBytes { bufferPointer in
            bufferPointer.bindMemory(to: resultType).baseAddress?.pointee
        }

        guard let v = value else {
            return "0"
        }

        if decimalSwitch.selectedSegmentIndex == 1 {
            return String(format: "0x%llX", v as! CVarArg)
        } else {
            return "\(v)"
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DataInspector.signedSwitchOn = signedSwitch.selectedSegmentIndex == 1
        DataInspector.decimalSwitchOn = decimalSwitch.selectedSegmentIndex == 1
        DataInspector.littleEndianSwitchOn = littleEndianSwitch.selectedSegmentIndex == 1
    }

    private func calculate<T: FixedWidthInteger>(_ type: T.Type) -> String {
        let byteCount = type.bitWidth / 8
        let maxLength = min(byteCount, bytes.count)
        var buffer = Array(bytes[..<maxLength])
        if littleEndianSwitch.selectedSegmentIndex == 1 {
            buffer.reverse()
        }
        while buffer.count < byteCount {
            buffer.append(0)
        }

        return resultToText(resultType: type, buffer: buffer)
    }
}
