import GladysCommon
import GladysUI
import GladysUIKit
import UIKit
import UniformTypeIdentifiers

final class PlistEditorCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!

    @IBOutlet private var topDistance: NSLayoutConstraint!
    @IBOutlet private var bottomDistance: NSLayoutConstraint!

    var arrayMode = false {
        didSet {
            if arrayMode {
                topDistance.constant = 8
                bottomDistance.constant = 8
            } else {
                topDistance.constant = 2
                bottomDistance.constant = 2
            }
        }
    }
}

final class PlistEditor: GladysViewController, UITableViewDataSource, UITableViewDelegate {
    var propertyList: Any!

    private var arrayMode = false

    @IBOutlet private var table: UITableView!
    @IBOutlet private var backgroundView: UIImageView!
    @IBOutlet private var copyButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        arrayMode = propertyList is [Any]
        table.tableFooterView = UIView(frame: .zero)
        doneButtonLocation = .right
        if !shouldEnableCopyButton, let i = navigationItem.rightBarButtonItems?.firstIndex(of: copyButton) {
            navigationItem.rightBarButtonItems?.remove(at: i)
        }
    }

    @IBAction private func copySelected(_: UIBarButtonItem) {
        if let p = propertyList as? [AnyHashable: Any],
           let mimeType = p["WebResourceMIMEType"] as? String,
           let data = p["WebResourceData"] as? Data,
           let uti = UTType(mimeType: mimeType) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: uti.identifier, visibility: .all) { callback -> Progress? in
                callback(data, nil)
                return nil
            }
            let titleString: String?
            if let url = p["WebResourceURL"] as? String {
                titleString = mimeType + " from " + url
            } else {
                titleString = mimeType
            }
            if case .success = Model.pasteItems(from: [provider], overrides: ImportOverrides(title: titleString, note: nil, labels: nil)) {
                Task {
                    await genericAlert(title: nil, message: "Extracted as new item", buttonTitle: nil)
                }
            }
        }
    }

    private func title(at index: Int) -> String? {
        if propertyList is [Any] {
            return "Item \(index)"
        } else if let p = propertyList as? [AnyHashable: Any] {
            return p.keys.sorted { $0.hashValue < $1.hashValue }[index] as? String ?? "<unkown>"
        } else {
            return nil
        }
    }

    private func value(at index: Int) -> Any? {
        if let p = propertyList as? [Any] {
            return p[index]
        } else if let p = propertyList as? [AnyHashable: Any] {
            let key = p.keys.sorted { $0.hashValue < $1.hashValue }[index]
            return p[key]
        } else {
            return nil
        }
    }

    private func selectable(at index: Int) -> Bool {
        let v = value(at: index)
        if let v = v as? [Any] {
            return !v.isEmpty
        } else if let v = v as? [AnyHashable: Any] {
            return !v.isEmpty
        } else if let v = v as? Data {
            return !v.isEmpty
        }
        return false
    }

    private func description(at index: Int) -> String {
        let v = value(at: index)
        if let v = v as? [Any] {
            let c = v.count
            if c == 0 {
                return "Empty list"
            } else if c == 1 {
                return "List of one item"
            } else {
                return "List of \(c) items"
            }

        } else if let v = v as? [AnyHashable: Any] {
            let c = v.keys.count
            if c == 0 {
                return "Dictionary, empty"
            } else if c == 1 {
                return "Dictionary, 1 item"
            } else {
                return "Dictionary, \(c) items"
            }

        } else if let v = v as? Data {
            if v.isEmpty {
                return "Data, empty"
            } else {
                let c = Int64(v.count)
                let countText = diskSizeFormatter.string(fromByteCount: c)
                return "Data, \(countText)"
            }

        } else if let v = v as? String {
            if v.isEmpty {
                return "Text, empty"
            } else {
                return "\"\(v)\""
            }

        } else if let v = v as? NSNumber {
            return v.description

        } else if let v {
            let desc = String(describing: v)
            if desc.isEmpty {
                return "<no description>"
            } else if desc.contains("CFKeyedArchiverUID") {
                return "CFKeyedArchiverUID: " + String(valueForKeyedArchiverUID(v))
            } else {
                return desc
            }
        }
        return "<unknown>"
    }

    private func subtitle(at index: Int) -> String? {
        let v = value(at: index)
        if let v = v as? [AnyHashable: Any], let url = v["WebResourceURL"] as? String {
            return url
        }
        return nil
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        if let p = propertyList as? [Any] {
            return p.count
        } else if let p = propertyList as? [AnyHashable: Any] {
            return p.keys.count
        } else {
            abort()
        }
    }

    private var shouldEnableCopyButton: Bool {
        if let p = propertyList as? [AnyHashable: Any],
           let mimeType = p["WebResourceMIMEType"] as? String,
           p["WebResourceData"] as? Data != nil {
            return UTType(mimeType: mimeType) != nil
        }
        return false
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlistEntryCell") as! PlistEditorCell
        cell.accessoryType = selectable(at: indexPath.row) ? .disclosureIndicator : .none
        cell.arrayMode = arrayMode
        let d = description(at: indexPath.row)
        if arrayMode {
            cell.titleLabel.text = d
            cell.subtitleLabel.text = subtitle(at: indexPath.row)
        } else {
            cell.titleLabel.text = title(at: indexPath.row)
            cell.subtitleLabel.text = d
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selectable(at: indexPath.row) {
            let v = value(at: indexPath.row)
            if v is [Any] || v is [AnyHashable: Any] {
                let editor = storyboard?.instantiateViewController(withIdentifier: "PlistEditor") as! PlistEditor
                editor.propertyList = v
                editor.title = title(at: indexPath.row)
                navigationController?.pushViewController(editor, animated: true)

            } else if let v = v as? Data {
                segue("hexEdit", sender: ("Data", v))
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let destination = segue.destination as? HexEdit, let data = sender as? (String, Data) {
            destination.title = data.0
            destination.bytes = data.1
        }
    }

    ///////////////////////////////////

    private var lastSize = CGSize.zero

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        if lastSize != view.frame.size, !view.frame.isEmpty {
            lastSize = view.frame.size
            let H = max(table.contentSize.height, 50)
            preferredContentSize = CGSize(width: preferredContentSize.width, height: H)
        }
    }
}

extension UINavigationController {
    override open func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        if let container = container as? GladysViewController {
            let p = container.preferredContentSize
            preferredContentSize = CGSize(width: p.width, height: p.height)
        } else {
            super.preferredContentSizeDidChange(forChildContentContainer: container)
        }
    }
}
