import Foundation
import SwiftData
import CoreLocation

/// A user route: imported from GPX or saved from a recorded ride. Coordinates
/// are stored flat as [lat, lon, lat, lon, …] (and optional elevations) so the
/// model stays a single row.
@Model
final class SavedRoute {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// "gpx" | "ride"
    var source: String = "gpx"
    var distanceMeters: Double = 0
    var elevationGainMeters: Double = 0
    var latLons: [Double] = []
    var elevations: [Double] = []

    init(name: String, source: String, coordinates: [CLLocationCoordinate2D], elevations: [Double]) {
        self.name = name
        self.source = source
        self.latLons = coordinates.flatMap { [$0.latitude, $0.longitude] }
        self.elevations = elevations
        self.distanceMeters = Self.length(of: coordinates)
        self.elevationGainMeters = Self.gain(of: elevations)
    }

    var coordinates: [CLLocationCoordinate2D] {
        stride(from: 0, to: latLons.count - 1, by: 2).map {
            CLLocationCoordinate2D(latitude: latLons[$0], longitude: latLons[$0 + 1])
        }
    }

    var start: CLLocationCoordinate2D? { coordinates.first }

    var isLoop: Bool {
        guard let a = coordinates.first, let b = coordinates.last, coordinates.count > 2 else { return false }
        return CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < 400
    }

    static func length(of coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<coords.count {
            total += CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                .distance(from: CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude))
        }
        return total
    }

    static func gain(of elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        var gain = 0.0, last = elevations[0]
        for e in elevations.dropFirst() where abs(e - last) >= 1 {
            if e > last { gain += e - last }
            last = e
        }
        return gain
    }
}
