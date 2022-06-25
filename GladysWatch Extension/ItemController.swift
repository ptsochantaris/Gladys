import WatchConnectivity
import WatchKit

private let formatter: DateFormatter = {
    let d = DateFormatter()
    d.dateStyle = .medium
    d.timeStyle = .medium
    d.doesRelativeDateFormatting = true
    return d
}()

extension Notification.Name {
    static let GroupsUpdated = Notification.Name("GroupsUpdated")
}

final class ItemController: WKInterfaceController {
    @IBOutlet private var label: WKInterfaceLabel!
    @IBOutlet private var date: WKInterfaceLabel!
    @IBOutlet private var image: WKInterfaceImage!
    @IBOutlet private var copyLabel: WKInterfaceLabel!
    @IBOutlet private var topGroup: WKInterfaceGroup!
    @IBOutlet private var bottomGroup: WKInterfaceGroup!
    @IBOutlet private var menuView: WKInterfaceGroup!

    private var gotImage = false
    private var context: [String: Any]!
    private var active = false
    private var observer: NSObjectProtocol?

    override func awake(withContext context: Any?) {
        self.context = context as? [String: Any]

        setTitle(self.context["it"] as? String)

        label.setText(labelText)
        date.setText(formatter.string(from: itemDate))

        topGroup.setBackgroundImage(ItemController.topShade)
        bottomGroup.setBackgroundImage(ItemController.bottomShade)

        observer = NotificationCenter.default.addObserver(forName: .GroupsUpdated, object: nil, queue: OperationQueue.main) { [weak self] _ in
            self?.updateGroups()
        }
        updateGroups()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private var labelText: String? {
        context["t"] as? String
    }

    private var uuid: String? {
        context["u"] as? String
    }

    private var itemDate: Date {
        context["d"] as? Date ?? .distantPast
    }

    override func willActivate() {
        super.willActivate()

        if active || ExtensionDelegate.currentUUID.isEmpty, let uuid = uuid {
            ExtensionDelegate.currentUUID = uuid
        }

        active = true

        if !gotImage, !fetchingImage {
            fetchImage()
        }
    }

    override func willDisappear() {
        super.willDisappear()
        ExtensionDelegate.currentUUID = ""
        if menuVisible {
            showMenu(false)
        }
    }

    private static let topShade = makeGradient(up: true)

    private static let bottomShade = makeGradient(up: false)

    private static func makeGradient(up: Bool) -> UIImage {
        let context = CGContext(data: nil,
                                width: 1,
                                height: 255,
                                bitsPerComponent: 8,
                                bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!

        let components: [CGFloat] = [0.0, 0.0, 0.0, 0.0,
                                     0.0, 0.0, 0.0, 0.4,
                                     0.0, 0.0, 0.0, 0.5]
        let locations: [CGFloat] = [0.0, 0.9, 1.0]
        let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: components, locations: locations, count: 3)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: up ? 0 : 255), end: CGPoint(x: 0, y: up ? 255 : 0), options: [])
        return UIImage(cgImage: context.makeImage()!)
    }

    private func fetchImage() {
        guard let uuid = uuid else { return }

        let cacheKey = uuid + String(itemDate.timeIntervalSinceReferenceDate) + ".dat"
        if let data = ImageCache.imageData(for: cacheKey), let i = UIImage(data: data) {
            image.setImage(i)
            fetchingImage = false
            gotImage = true
            return
        }

        fetchingImage = true

        var size = contentFrame.size
        size.width *= 2
        size.height *= 2
        WCSession.default.sendMessage(["image": uuid, "width": size.width, "height": size.height], replyHandler: { reply in
            if let r = reply["image"] as? Data {
                let i = UIImage(data: r)
                if i != nil {
                    ImageCache.setImageData(r, for: cacheKey)
                }
                DispatchQueue.main.async {
                    self.image.setImage(i)
                    self.fetchingImage = false
                    self.gotImage = true
                }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.image.setImage(nil)
                self.fetchingImage = false
                self.gotImage = false
            }
        })
    }

    private var fetchingImage = false {
        didSet {
            topGroup.setHidden(ItemController.hidden)
            bottomGroup.setHidden(ItemController.hidden)
            image.setHidden(false)
            copyLabel.setText("…")
            copyLabel.setHidden(!fetchingImage)
        }
    }

    private var copying = false {
        didSet {
            topGroup.setHidden(copying || ItemController.hidden)
            bottomGroup.setHidden(copying || ItemController.hidden)
            image.setHidden(copying)
            copyLabel.setText("Copying")
            copyLabel.setHidden(!copying)
        }
    }

    private var deleting = false {
        didSet {
            topGroup.setHidden(deleting || ItemController.hidden)
            bottomGroup.setHidden(deleting || ItemController.hidden)
            image.setHidden(deleting)
            copyLabel.setText("Deleting")
            copyLabel.setHidden(!deleting)
        }
    }

    private var opening = false {
        didSet {
            topGroup.setHidden(opening || ItemController.hidden)
            bottomGroup.setHidden(opening || ItemController.hidden)
            image.setHidden(opening)
            copyLabel.setText("Opening item in the phone app")
            copyLabel.setHidden(!opening)
        }
    }

    private var topping = false {
        didSet {
            topGroup.setHidden(topping || ItemController.hidden)
            bottomGroup.setHidden(topping || ItemController.hidden)
            image.setHidden(topping)
            copyLabel.setText("Moving to the top of the list")
            copyLabel.setHidden(!topping)
        }
    }

    @IBAction private func viewOnDeviceSelected() {
        showMenu(false)
        if let uuid = uuid {
            opening = true
            WCSession.default.sendMessage(["view": uuid], replyHandler: { _ in
                DispatchQueue.main.async {
                    self.opening = false
                }
            }, errorHandler: { _ in
                DispatchQueue.main.async {
                    self.opening = false
                }
            })
        }
    }

    @IBAction private func copySelected() {
        showMenu(false)
        if let uuid = uuid {
            copying = true
            WCSession.default.sendMessage(["copy": uuid], replyHandler: { _ in
                DispatchQueue.main.async {
                    self.copying = false
                }
            }, errorHandler: { _ in
                DispatchQueue.main.async {
                    self.copying = false
                }
            })
        }
    }

    @IBAction private func moveToTopSelected() {
        showMenu(false)
        if let uuid = uuid {
            topping = true
            WCSession.default.sendMessage(["moveToTop": uuid], replyHandler: { _ in
                DispatchQueue.main.async {
                    self.topping = false
                }
            }, errorHandler: { _ in
                DispatchQueue.main.async {
                    self.topping = false
                }
            })
        }
    }

    @IBAction private func deleteSelected() {
        showMenu(false)
        if let uuid = uuid {
            deleting = true
            WCSession.default.sendMessage(["delete": uuid], replyHandler: { _ in
                DispatchQueue.main.async {
                    self.deleting = false
                }
            }, errorHandler: { _ in
                DispatchQueue.main.async {
                    self.deleting = false
                }
            })
        }
    }

    private static var hidden = false
    @IBAction private func tapped(_: WKTapGestureRecognizer) {
        ItemController.hidden = !ItemController.hidden
        NotificationCenter.default.post(name: .GroupsUpdated, object: nil)
    }

    private func updateGroups() {
        topGroup.setHidden(ItemController.hidden)
        bottomGroup.setHidden(ItemController.hidden)
    }

    private var menuVisible = false
    private func showMenu(_ show: Bool) {
        menuVisible = show
        if show {
            menuView.setAlpha(0)
            menuView.setHidden(false)
            animate(withDuration: 0.2) {
                self.menuView.setAlpha(1)
            }

        } else {
            animate(withDuration: 0.2) {
                self.menuView.setAlpha(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.menuView.setHidden(true)
            }
        }
    }

    @IBAction private func longPress(_ press: WKLongPressGestureRecognizer) {
        if press.state == .began {
            showMenu(!menuVisible)
        }
    }
}
