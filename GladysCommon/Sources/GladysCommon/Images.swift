import CoreLocation
import MapKit

extension CLLocationCoordinate2D: Hashable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

extension CGSize: Hashable {
    public static func == (lhs: CGSize, rhs: CGSize) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

public protocol DisplayImageProviding {
    var imageCacheKey: String { get }
    var displayIcon: IMAGE { get }
}

public final class Images {
    private let cache = Cache<String, IMAGE>()

    public static let shared = Images()

    public func image(for item: DisplayImageProviding) -> IMAGE? {
        let cacheKey = item.imageCacheKey
        if let cachedImage = cache[cacheKey] {
            return cachedImage
        } else {
            let image = item.displayIcon
            cache[cacheKey] = image
            return image
        }
    }

    public subscript(key: String) -> IMAGE? {
        get {
            cache[key]
        }
        set {
            cache[key] = newValue
        }
    }

    public func reset() {
        cache.reset()
    }

    public struct SnapshotOptions: Hashable {
        public var coordinate: CLLocationCoordinate2D?
        public let range: CLLocationDistance
        public let outputSize: CGSize

        public init(coordinate: CLLocationCoordinate2D? = nil, range: CLLocationDistance = 0, outputSize: CoreFoundation.CGSize = .zero) {
            self.coordinate = coordinate
            self.range = range
            self.outputSize = outputSize
        }
    }

    #if !os(watchOS)
        public func mapSnapshot(with options: SnapshotOptions) async throws -> IMAGE {
            guard let coordinate = options.coordinate else {
                throw GladysError.noData.error
            }
            let O = MKMapSnapshotter.Options()
            O.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: options.range, longitudinalMeters: options.range)
            O.size = options.outputSize
            O.showsBuildings = true
            O.pointOfInterestFilter = .includingAll
            return try await MKMapSnapshotter(options: O).start().image
        }
    #endif
}
