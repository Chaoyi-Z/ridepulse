import Foundation

/// Speed/distance unit preference, persisted via @AppStorage("speedUnit").
enum SpeedUnit: String, CaseIterable {
    case mph
    case kmh

    var label: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "km/h"
        }
    }

    var distanceLabel: String {
        switch self {
        case .mph: return "mi"
        case .kmh: return "km"
        }
    }

    func speedString(mps: Double) -> String {
        let value = self == .mph ? mps * 2.23694 : mps * 3.6
        return String(format: "%.1f", value)
    }

    func distanceString(meters: Double) -> String {
        let value = self == .mph ? meters / 1609.344 : meters / 1000.0
        return String(format: "%.2f", value)
    }

    static func fromStored(_ raw: String) -> SpeedUnit {
        SpeedUnit(rawValue: raw) ?? .mph
    }
}

/// Formatting helpers and GPX export for rides.
enum RideStore {
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Valid GPX 1.1 with track points (lat/lon, elevation, time) and
    /// power/heart-rate extensions (Garmin TrackPointExtension for HR).
    static func gpxString(for ride: Ride) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="RidePulse" \
        xmlns="http://www.topografix.com/GPX/1/1" \
        xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <metadata>
            <name>RidePulse Ride</name>
            <time>\(iso.string(from: ride.startDate))</time>
          </metadata>
          <trk>
            <name>Ride \(iso.string(from: ride.startDate))</name>
            <trkseg>

        """
        let sorted = ride.samples.sorted { $0.timestamp < $1.timestamp }
        for sample in sorted {
            guard let lat = sample.latitude, let lon = sample.longitude else { continue }
            xml += "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\">\n"
            if let ele = sample.altitude {
                xml += "        <ele>\(ele)</ele>\n"
            }
            xml += "        <time>\(iso.string(from: sample.timestamp))</time>\n"
            if sample.powerWatts != nil || sample.heartRateBpm != nil {
                xml += "        <extensions>\n"
                if let hr = sample.heartRateBpm {
                    xml += """
                              <gpxtpx:TrackPointExtension>
                                <gpxtpx:hr>\(hr)</gpxtpx:hr>
                              </gpxtpx:TrackPointExtension>

                    """
                }
                if let power = sample.powerWatts {
                    xml += "          <power>\(power)</power>\n"
                }
                xml += "        </extensions>\n"
            }
            xml += "      </trkpt>\n"
        }
        xml += """
            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }

    /// Writes the ride's GPX to a temp file and returns its URL (for ShareLink).
    static func gpxFileURL(for ride: Ride) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let filename = "ridepulse-\(formatter.string(from: ride.startDate)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try gpxString(for: ride).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
