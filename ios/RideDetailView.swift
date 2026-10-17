import SwiftUI
import SwiftData
import Charts
import MapKit

struct RideDetailView: View {
    let ride: Ride
    /// True when shown as the post-ride summary sheet (adds a completion header).
    var isSummary = false
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    @AppStorage(RiderProfile.ftpKey) private var ftpWatts: Int = 0
    @AppStorage(RiderProfile.maxHRKey) private var maxHRBpm: Int = 0
    @State private var gpxURL: URL?
    @State private var savedRouteName: String?
    @State private var exportMessage: String?
    @State private var exporting = false
    @EnvironmentObject private var health: HealthExporter
    @EnvironmentObject private var strava: StravaService
    @Environment(\.modelContext) private var modelContext

    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }
    private var stats: RideStats {
        RideStats(ride: ride, ftp: ftpWatts > 0 ? ftpWatts : nil, maxHR: maxHRBpm > 0 ? maxHRBpm : nil)
    }

    private var sortedSamples: [RideSample] {
        ride.samples.sorted { $0.timestamp < $1.timestamp }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        sortedSamples.compactMap { sample in
            guard let lat = sample.latitude, let lon = sample.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private var routeRegion: MKCoordinateRegion? {
        let coords = routeCoordinates
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isSummary {
                    completionHeader
                }

                // Summary stats — distance & duration first, then the rest.
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(
                        value: unit.distanceString(meters: ride.distanceMeters),
                        unit: unit.distanceLabel,
                        label: "Distance",
                        accent: .green
                    )
                    MetricTile(
                        value: RideStore.formatDuration(ride.durationSeconds),
                        unit: "active",
                        label: "Duration",
                        accent: .purple
                    )
                    MetricTile(
                        value: ride.avgPowerWatts > 0 ? "\(Int(ride.avgPowerWatts))" : "--",
                        unit: "W",
                        label: "Avg Power",
                        accent: .red
                    )
                    MetricTile(
                        value: ride.maxPowerWatts > 0 ? "\(ride.maxPowerWatts)" : "--",
                        unit: "W",
                        label: "Max Power",
                        accent: .red
                    )
                    MetricTile(
                        value: ride.avgHeartRate > 0 ? "\(Int(ride.avgHeartRate))" : "--",
                        unit: "bpm",
                        label: "Avg HR",
                        accent: .pink
                    )
                    MetricTile(
                        value: ride.maxHeartRate > 0 ? "\(ride.maxHeartRate)" : "--",
                        unit: "bpm",
                        label: "Max HR",
                        accent: .pink
                    )
                    MetricTile(
                        value: unit.speedString(mps: ride.avgSpeedMps),
                        unit: unit.label,
                        label: "Avg Speed",
                        accent: .blue
                    )
                    MetricTile(
                        value: unit.speedString(mps: ride.maxSpeedMps),
                        unit: unit.label,
                        label: "Max Speed",
                        accent: .blue
                    )
                }

                // Derived statistics
                detailStats

                // Route map
                VStack(alignment: .leading, spacing: 8) {
                    Text("Route")
                        .font(.headline)
                    if let region = routeRegion {
                        Map(initialPosition: .region(region)) {
                            MapPolyline(coordinates: routeCoordinates)
                                .stroke(.blue, lineWidth: 4)
                            if let start = routeCoordinates.first {
                                Marker("Start", systemImage: "flag.fill", coordinate: start)
                                    .tint(.green)
                            }
                            if routeCoordinates.count > 1, let end = routeCoordinates.last {
                                Marker("End", systemImage: "flag.checkered", coordinate: end)
                                    .tint(.red)
                            }
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text("No GPS data recorded for this ride.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                // Charts
                VStack(alignment: .leading, spacing: 8) {
                    Text("Effort Over Time")
                        .font(.headline)
                    rideChart
                        .frame(height: 220)
                }

                // Ride this again: save the track as a navigable route.
                if routeCoordinates.count > 10 {
                    Button {
                        saveAsRoute()
                    } label: {
                        Label(savedRouteName == nil ? "Save as route (ride this again)" : "Saved to My Routes ✓",
                              systemImage: "map")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(savedRouteName == nil ? Color.green : Color(.secondarySystemBackground))
                            .foregroundStyle(savedRouteName == nil ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(savedRouteName != nil)
                }

                // Apple Health / Strava
                HStack(spacing: 12) {
                    Button {
                        exporting = true
                        Task {
                            if let id = await health.save(ride) {
                                ride.healthWorkoutUUID = id.uuidString
                                try? modelContext.save()
                            }
                            exportMessage = health.lastMessage
                            exporting = false
                        }
                    } label: {
                        Label(ride.healthWorkoutUUID == nil ? "Save to Health" : "In Health ✓", systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.pink.opacity(ride.healthWorkoutUUID == nil ? 1 : 0.15))
                            .foregroundStyle(ride.healthWorkoutUUID == nil ? .white : .pink)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(exporting || ride.healthWorkoutUUID != nil)

                    Button {
                        exporting = true
                        Task {
                            do {
                                let id = try await strava.upload(ride, name: "Ride · \(RideStore.formatDate(ride.startDate))")
                                ride.stravaActivityID = id
                                try? modelContext.save()
                                exportMessage = "Uploaded to Strava."
                            } catch {
                                exportMessage = "Strava: \(error.localizedDescription)"
                            }
                            exporting = false
                        }
                    } label: {
                        Label(ride.stravaActivityID == nil ? "Upload to Strava" : "On Strava ✓", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.orange.opacity(ride.stravaActivityID == nil ? 1 : 0.15))
                            .foregroundStyle(ride.stravaActivityID == nil ? .white : .orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(exporting || ride.stravaActivityID != nil || !strava.isConnected)
                }
                if !strava.isConnected && ride.stravaActivityID == nil {
                    Text("Connect Strava in Settings to upload rides.").font(.caption).foregroundStyle(.secondary)
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let id = ride.stravaActivityID, let url = URL(string: "https://www.strava.com/activities/\(id)") {
                    Link("View on Strava", destination: url).font(.caption)
                }

                // GPX export
                if let gpxURL = gpxURL {
                    ShareLink(item: gpxURL) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(isSummary ? "Ride Complete" : RideStore.formatDate(ride.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            gpxURL = RideStore.gpxFileURL(for: ride)
        }
    }

    private func saveAsRoute() {
        let coords = routeCoordinates
        let eles = sortedSamples.compactMap { s -> Double? in
            (s.latitude != nil && s.longitude != nil) ? (s.altitude ?? .nan) : nil
        }
        let name = "Ride · \(RideStore.formatDate(ride.startDate))"
        let route = SavedRoute(name: name, source: "ride", coordinates: coords,
                               elevations: eles.contains(where: { $0.isNaN }) ? [] : eles)
        modelContext.insert(route)
        try? modelContext.save()
        savedRouteName = name
    }

    // MARK: - Summary header & detailed stats

    private var completionHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Nice ride!")
                .font(.title2.bold())
            Text("\(RideStore.formatDate(ride.startDate)) · \(unit.distanceString(meters: ride.distanceMeters)) \(unit.distanceLabel) in \(RideStore.formatDuration(ride.durationSeconds))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var detailStats: some View {
        let s = stats
        let elevUnit = unit == .mph ? "ft" : "m"
        let elevFactor = unit == .mph ? 3.28084 : 1.0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Ride Statistics")
                .font(.headline)
            VStack(spacing: 0) {
                statRow("Elapsed time", RideStore.formatDuration(s.elapsedSeconds))
                statRow("Moving time", RideStore.formatDuration(s.movingSeconds))
                if s.elapsedSeconds > 0 {
                    statRow("Stopped", RideStore.formatDuration(max(0, s.elapsedSeconds - s.movingSeconds)))
                }
                statRow("Elevation gain", String(format: "%.0f %@", s.elevationGainMeters * elevFactor, elevUnit))
                statRow("Elevation loss", String(format: "%.0f %@", s.elevationLossMeters * elevFactor, elevUnit))
                if let np = s.normalizedPower {
                    statRow("Normalized power", "\(Int(np.rounded())) W")
                }
                if let vi = s.variabilityIndex {
                    statRow("Variability index", String(format: "%.2f", vi))
                }
                if let iff = s.intensityFactor {
                    statRow("Intensity factor", String(format: "%.2f", iff))
                }
                if let tss = s.tss {
                    statRow("Training stress (TSS)", "\(Int(tss.rounded()))")
                }
                if let kj = s.workKilojoules {
                    statRow("Work", "\(Int(kj.rounded())) kJ")
                }
                if let kcal = s.estimatedCalories {
                    statRow("Calories (est.)", "\(Int(kcal.rounded())) kcal")
                }
                statRow("Samples", "\(ride.samples.count)", last: true)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if !s.peakPower.isEmpty {
                Text("Peak Power")
                    .font(.headline)
                    .padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach(s.peakPower, id: \.seconds) { peak in
                        VStack(spacing: 2) {
                            Text("\(peak.watts)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.red)
                            Text("W")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(RideStats.windowLabel(peak.seconds))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if !s.powerZones.isEmpty {
                HStack {
                    Text(s.powerZonesUseFTP ? "Power Zones" : "Effort Distribution")
                        .font(.headline)
                    Spacer()
                    if s.powerZonesUseFTP {
                        Text("FTP \(ftpWatts) W").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                ZoneBars(zones: s.powerZones)
                if !s.powerZonesUseFTP {
                    Text("Set your FTP in Settings › Rider Profile for Coggan zones, Intensity Factor and TSS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !s.heartRateZones.isEmpty {
                HStack {
                    Text("Heart Rate Zones").font(.headline)
                    Spacer()
                    Text("Max \(maxHRBpm) bpm").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                ZoneBars(zones: s.heartRateZones)
            } else if ride.maxHeartRate > 0 && maxHRBpm == 0 {
                Text("Set your max heart rate in Settings › Rider Profile to see HR zones.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statRow(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if !last {
                Divider().padding(.leading, 14)
            }
        }
    }

    // MARK: - Chart

    private var rideChart: some View {
        let start = ride.startDate
        let powerPoints: [(Double, Double)] = sortedSamples.compactMap { s in
            guard let p = s.powerWatts else { return nil }
            return (s.timestamp.timeIntervalSince(start) / 60.0, Double(p))
        }
        let hrPoints: [(Double, Double)] = sortedSamples.compactMap { s in
            guard let h = s.heartRateBpm else { return nil }
            return (s.timestamp.timeIntervalSince(start) / 60.0, Double(h))
        }
        let speedPoints: [(Double, Double)] = sortedSamples.map { s in
            (s.timestamp.timeIntervalSince(start) / 60.0, unit == .mph ? s.speedMps * 2.23694 : s.speedMps * 3.6)
        }

        return Chart {
            ForEach(Array(powerPoints.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Min", point.0),
                    y: .value("Watts", point.1)
                )
                .foregroundStyle(by: .value("Metric", "Power (W)"))
            }
            ForEach(Array(hrPoints.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Min", point.0),
                    y: .value("BPM", point.1)
                )
                .foregroundStyle(by: .value("Metric", "HR (bpm)"))
            }
            ForEach(Array(speedPoints.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Min", point.0),
                    y: .value("Speed", point.1)
                )
                .foregroundStyle(by: .value("Metric", "Speed (\(unit.label))"))
            }
        }
        .chartForegroundStyleScale([
            "Power (W)": Color.red,
            "HR (bpm)": Color.green,
            "Speed (\(unit.label))": Color.blue
        ])
        .chartXAxisLabel("Minutes")
    }
}

/// Horizontal time-in-zone bars.
struct ZoneBars: View {
    let zones: [ZoneTime]

    var body: some View {
        let total = max(1, zones.map(\.seconds).reduce(0, +))
        VStack(spacing: 8) {
            // Stacked overview strip
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(zones) { z in
                        Rectangle()
                            .fill(z.color)
                            .frame(width: max(0, geo.size.width * z.seconds / total))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            ForEach(zones) { z in
                HStack(spacing: 8) {
                    Circle().fill(z.color).frame(width: 8, height: 8)
                    Text(z.name).font(.caption)
                    Text(z.range).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((z.seconds / total * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                    Text(RideStore.formatDuration(z.seconds))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
