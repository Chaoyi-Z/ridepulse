import Foundation
import CoreLocation

/// Elevation profile for a route, fetched from the free Open-Meteo elevation API
/// (no key; ~90 m SRTM/Copernicus data). Routes are sampled every ~80 m and the
/// result is cached per route in memory for the session.
struct ElevationProfile {
    /// Metres along the route for each sample.
    let distances: [Double]
    /// Metres above sea level for each sample.
    let elevations: [Double]

    /// Elevation at a given distance along the route (linear interpolation).
    func elevation(at meters: Double) -> Double? {
        guard let first = distances.first, let last = distances.last, !elevations.isEmpty else { return nil }
        if meters <= first { return elevations[0] }
        if meters >= last { return elevations[elevations.count - 1] }
        var lo = 0, hi = distances.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if distances[mid] <= meters { lo = mid } else { hi = mid }
        }
        let span = distances[hi] - distances[lo]
        let t = span > 0 ? (meters - distances[lo]) / span : 0
        return elevations[lo] + (elevations[hi] - elevations[lo]) * t
    }

    /// Average grade (%) over the next `lookahead` metres from `meters`.
    func gradeAhead(from meters: Double, lookahead: Double = 400) -> Double? {
        guard let a = elevation(at: meters), let b = elevation(at: meters + lookahead),
              let last = distances.last, meters < last - 20 else { return nil }
        let run = min(lookahead, last - meters)
        return run > 0 ? (b - a) / run * 100 : nil
    }

    var totalGain: Double {
        guard elevations.count > 1 else { return 0 }
        var gain = 0.0, last = elevations[0]
        for e in elevations.dropFirst() where abs(e - last) >= 1 {
            if e > last { gain += e - last }
            last = e
        }
        return gain
    }
}

actor ElevationService {
    static let shared = ElevationService()
    private var cache: [String: ElevationProfile] = [:]

    func profile(for coordinates: [CLLocationCoordinate2D], cacheKey: String) async -> ElevationProfile? {
        if let cached = cache[cacheKey] { return cached }
        guard coordinates.count > 1 else { return nil }

        // Sample every ~80 m, keeping first and last points.
        var samples: [(Double, CLLocationCoordinate2D)] = [(0, coordinates[0])]
        var cumulative = 0.0
        var sinceLast = 0.0
        for i in 1..<coordinates.count {
            let d = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
                .distance(from: CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude))
            cumulative += d
            sinceLast += d
            if sinceLast >= 80 || i == coordinates.count - 1 {
                samples.append((cumulative, coordinates[i]))
                sinceLast = 0
            }
        }
        // Cap requests for very long routes (~ 100 points per call).
        let maxPoints = 1200
        if samples.count > maxPoints {
            let step = Double(samples.count) / Double(maxPoints)
            samples = stride(from: 0.0, to: Double(samples.count), by: step).map { samples[Int($0)] }
        }

        var elevations: [Double] = []
        elevations.reserveCapacity(samples.count)
        for chunk in stride(from: 0, to: samples.count, by: 100) {
            let slice = samples[chunk..<min(chunk + 100, samples.count)]
            let lats = slice.map { String(format: "%.5f", $0.1.latitude) }.joined(separator: ",")
            let lons = slice.map { String(format: "%.5f", $0.1.longitude) }.joined(separator: ",")
            guard let url = URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(lats)&longitude=\(lons)") else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                guard decoded.elevation.count == slice.count else { return nil }
                elevations.append(contentsOf: decoded.elevation)
            } catch {
                return nil
            }
        }
        // Light smoothing to take the edge off DEM noise.
        var smoothed = elevations
        if elevations.count > 4 {
            for i in 1..<(elevations.count - 1) {
                smoothed[i] = (elevations[i - 1] + elevations[i] * 2 + elevations[i + 1]) / 4
            }
        }
        let profile = ElevationProfile(distances: samples.map { $0.0 }, elevations: smoothed)
        cache[cacheKey] = profile
        return profile
    }

    private struct Response: Decodable { let elevation: [Double] }
}
