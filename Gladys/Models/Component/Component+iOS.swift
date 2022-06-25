import UIKit

extension Component {
    var componentIcon: UIImage? {
        get {
            UIImage.fromFile(imagePath, template: displayIconTemplate)
        }
        set {
            let ipath = imagePath
            if let n = newValue, let data = n.pngData() {
                try? data.write(to: ipath)
            } else {
                try? FileManager.default.removeItem(at: ipath)
            }
        }
    }
}
