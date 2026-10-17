import Foundation
import ActivityKit

/// Live Activity payload shared by the app (which starts/updates it) and the
/// widget extension (which renders it on the Lock Screen / Dynamic Island).
struct RideActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speedMps: Double
        var powerWatts: Int?
        var heartRateBpm: Int?
        var distanceMeters: Double
        var elapsedSeconds: Double
        /// "recording" | "paused" | "auto"
        var rideState: String
        var nextInstruction: String?
        var distanceToManeuverMeters: Double?
        var remainingMeters: Double?
        var useMetric: Bool
    }

    var startDate: Date
    var routeName: String?
}

// MARK: - Formatting helpers usable from both targets

enum RideActivityFormat {
    static func speed(_ mps: Double, metric: Bool) -> String {
        String(format: "%.1f", metric ? mps * 3.6 : mps * 2.23694)
    }
    static func speedUnit(metric: Bool) -> String { metric ? "km/h" : "mph" }

    static func distance(_ meters: Double, metric: Bool) -> String {
        String(format: "%.2f", metric ? meters / 1000 : meters / 1609.344)
    }
    static func distanceUnit(metric: Bool) -> String { metric ? "km" : "mi" }

    static func shortDistance(_ meters: Double, metric: Bool) -> String {
        if metric {
            return meters >= 950 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
        }
        let feet = meters * 3.28084
        return feet >= 900 ? String(format: "%.1f mi", feet / 5280) : "\(Int((feet / 10).rounded() * 10)) ft"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
