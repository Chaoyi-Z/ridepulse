import SwiftUI
import MapKit
import SwiftData

/// Full-screen turn-by-turn view: course-up map following the rider, the active
/// route and ridden track, the maneuver banner, live numbers and ride controls.
/// Keeps the screen awake while shown.
struct NavigationMapView: View {
    @EnvironmentObject private var planner: RoutePlanner
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var locationManager: LocationSpeedManager
    @EnvironmentObject private var bleManager: BLEPowerMeterManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @EnvironmentObject private var health: HealthExporter
    @EnvironmentObject private var strava: StravaService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var isFollowing = true
    @State private var lastHeading: CLLocationDirection = 0
    @State private var finishedRide: Ride?

    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                if let route = planner.activeRoute {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.green, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    Marker(route.name, systemImage: "flag.checkered", coordinate: route.destination)
                        .tint(.red)
                }
                if recorder.liveCoordinates.count > 1 {
                    MapPolyline(coordinates: recorder.liveCoordinates)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { }   // we draw our own recenter button
            .simultaneousGesture(
                // Any manual pan/zoom breaks follow mode until the rider recenters.
                DragGesture(minimumDistance: 10).onChanged { _ in isFollowing = false }
            )
            .simultaneousGesture(
                MagnifyGesture().onChanged { _ in isFollowing = false }
            )
            .ignoresSafeArea()

            // Top: maneuver banner
            VStack(spacing: 0) {
                NavigationBanner(planner: planner, unit: unit, speedMps: locationManager.speedMps)
                    .background(Color(.systemBackground).opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                Spacer()
            }

            // Right: recenter + close
            VStack(spacing: 12) {
                Spacer().frame(height: 170)
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        mapButton(systemImage: "chevron.down") { dismiss() }
                        if !isFollowing {
                            mapButton(systemImage: "location.north.line.fill") {
                                isFollowing = true
                                if let loc = locationManager.currentLocation { follow(loc, animated: true) }
                            }
                        }
                        mapButton(systemImage: "map") {
                            if let route = planner.activeRoute {
                                withAnimation { camera = .rect(route.mapRect.insetBy(dx: -1500, dy: -1500)) }
                                isFollowing = false
                            }
                        }
                    }
                    .padding(.trailing, 12)
                }
                Spacer()
            }

            // Bottom: live numbers + ride controls
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    if let profile = planner.elevationProfile, planner.activeRoute != nil {
                        ElevationProfileView(distances: profile.distances, elevations: profile.elevations,
                                             unit: unit, progressMeters: planner.progress?.alongRouteMeters)
                            .frame(height: 90)
                    }
                    HStack(spacing: 0) {
                        bigStat(unit.speedString(mps: locationManager.speedMps), unit.label, "Speed", .blue)
                        Divider().frame(height: 40)
                        bigStat(bleManager.powerWatts.map { "\($0)" } ?? "--", "W", "Power", .red)
                        Divider().frame(height: 40)
                        bigStat(watchManager.heartRateBpm.map { "\(Int($0.rounded()))" } ?? "--", "bpm", "HR", .pink)
                        Divider().frame(height: 40)
                        bigStat(unit.distanceString(meters: locationManager.tripDistanceMeters), unit.distanceLabel, "Dist", .green)
                        Divider().frame(height: 40)
                        bigStat(RideStore.formatDuration(recorder.elapsedSeconds), "", "Time", .purple)
                    }
                    rideControls
                }
                .padding(12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { loc in
            planner.update(with: loc)
            if isFollowing { follow(loc, animated: true) }
        }
        .onChange(of: planner.activeRoute == nil) { _, ended in
            if ended { dismiss() }
        }
        .sheet(item: $finishedRide) { ride in
            NavigationStack {
                RideDetailView(ride: ride, isSummary: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { finishedRide = nil }
                        }
                    }
            }
        }
    }

    /// Course-up, tilted camera a few hundred metres ahead of the rider — like a
    /// car/bike nav app. Heading comes from GPS course; keep the last good one
    /// when stopped (course is -1 below ~1 m/s).
    private func follow(_ loc: CLLocation, animated: Bool) {
        if loc.course >= 0, loc.speed > 1.0 { lastHeading = loc.course }
        let cam = MapCamera(centerCoordinate: loc.coordinate, distance: 650, heading: lastHeading, pitch: 55)
        if animated {
            withAnimation(.linear(duration: 0.9)) { camera = .camera(cam) }
        } else {
            camera = .camera(cam)
        }
    }

    // MARK: - Pieces

    private func mapButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }

    private func bigStat(_ value: String, _ unitLabel: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unitLabel.isEmpty {
                    Text(unitLabel).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rideControls: some View {
        switch recorder.state {
        case .idle:
            controlButton("Start Ride", "play.fill", .green) { recorder.startRide() }
        case .recording:
            HStack(spacing: 10) {
                controlButton("Pause", "pause.fill", .orange) { recorder.pauseRide() }
                controlButton("Finish", "stop.fill", .red) { finishAndSave() }
            }
        case .paused:
            HStack(spacing: 10) {
                controlButton("Resume", "play.fill", .green) { recorder.resumeRide() }
                controlButton("Finish", "stop.fill", .red) { finishAndSave() }
            }
        }
    }

    private func controlButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func finishAndSave() {
        if let ride = recorder.finishRide() {
            modelContext.insert(ride)
            try? modelContext.save()
            RideExport.runAutomatic(ride, health: health, strava: strava, context: modelContext)
            finishedRide = ride
        }
    }
}
