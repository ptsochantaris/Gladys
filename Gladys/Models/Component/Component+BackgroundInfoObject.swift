import MapKit

extension Component {
    var backgroundInfoObject: (Any?, Int) {
        switch representedClass {
        case .mapItem: return (decode() as? MKMapItem, 30)
        case .color: return (decode() as? COLOR, 30)
        default: return (nil, 0)
        }
    }
}
