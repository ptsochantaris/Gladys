import CoreLocation
import MapKit

extension MKMapItem: @retroactive @unchecked Sendable {}

extension CLLocationCoordinate2D: @retroactive Equatable {}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

public let imageDimensions = CGSize(width: 512, height: 512)

@MainActor
public protocol DisplayImageProviding {
    var imageCacheKey: String { get }
    var displayIcon: IMAGE { get async }
}

public enum Images {
    public struct SnapshotOptions: Hashable, Sendable {
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
        public static func mapSnapshot(with options: SnapshotOptions) async throws -> IMAGE {
            guard let coordinate = options.coordinate else {
                throw GladysError.noData
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
