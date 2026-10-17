import SwiftUI
import MapKit
import SwiftData

/// Big live metric tile.
struct MetricTile: View {
    let value: String
    let unit: String
    let label: String
    var accent: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Connection status dot.
struct StatusDot: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Live GPS map card. While recording, draws the route so far as a polyline;
/// otherwise shows just the user's location.
struct RideMapCard: View {
    @ObservedObject var recorder: RideRecorder
    @ObservedObject var planner: RoutePlanner
    @State private var cameraPosition: MapCameraPosition =
        .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        Map(position: $cameraPosition) {
            if let route = planner.activeRoute {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.green, lineWidth: 6)
                Marker(route.name, systemImage: "flag.checkered", coordinate: route.destination)
                    .tint(.red)
            }
            if !recorder.liveCoordinates.isEmpty {
                MapPolyline(coordinates: recorder.liveCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .frame(height: planner.activeRoute == nil ? 220 : 300)
        .allowsHitTesting(false)   // the card is a preview; taps open full-screen navigation
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .onChange(of: planner.activeRoute?.name) { _, name in
            // Frame the whole route when one is chosen, then follow the rider.
            if let route = planner.activeRoute {
                cameraPosition = .rect(route.mapRect.insetBy(dx: -1500, dy: -1500))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    guard planner.activeRoute?.name == name else { return }
                    cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
                }
            } else {
                cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
            }
        }
    }
}

/// Turn-by-turn banner shown above the map while navigating.
struct NavigationBanner: View {
    @ObservedObject var planner: RoutePlanner
    let unit: SpeedUnit
    let speedMps: Double
    /// When set, shows a "Full screen" button that opens NavigationMapView.
    var onExpand: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let route = planner.activeRoute {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: maneuverSymbol(planner.progress?.nextInstruction))
                        .font(.system(size: 34, weight: .bold))
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        if let p = planner.progress {
                            if p.hasArrived {
                                Text("You've arrived").font(.title3.bold())
                                Text(route.name).font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text(RoutePlanner.shortDistance(p.distanceToManeuverMeters, unit: unit))
                                    .font(.title2.bold().monospacedDigit())
                                Text(p.nextInstruction)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                        } else {
                            Text("Navigating to \(route.name)").font(.headline)
                            Text(route.steps.first?.instruction ?? "Waiting for GPS…")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        planner.stopNavigation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    if let p = planner.progress {
                        Label("\(RoutePlanner.shortDistance(p.remainingMeters, unit: unit)) left",
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        if speedMps > 1.0 {
                            let eta = Date().addingTimeInterval(p.remainingMeters / speedMps)
                            Label(eta.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        }
                        if p.isOffRoute {
                            Label("Off route", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else if let g = p.gradeAheadPercent, abs(g) >= 1.5 {
                            Label(String(format: "%.1f%% ahead", g),
                                  systemImage: g > 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(g >= 6 ? .red : (g > 0 ? .orange : .teal))
                                .fontWeight(.semibold)
                        }
                    } else {
                        Label("\(RoutePlanner.shortDistance(route.totalMeters, unit: unit)) total",
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    Spacer()
                    if let onExpand {
                        Button(action: onExpand) {
                            Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    if let url = planner.appleMapsCyclingURL() {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Apple Maps", systemImage: "arrow.up.forward.app")
                        }
                        .font(.caption)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((planner.progress?.isOffRoute ?? false) ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke((planner.progress?.isOffRoute ?? false) ? Color.orange : Color.green, lineWidth: 1)
            )
        }
    }

    private func maneuverSymbol(_ instruction: String?) -> String {
        guard let s = instruction?.lowercased() else { return "location.north.line.fill" }
        if s.contains("arrive") || s.contains("destination") { return "flag.checkered" }
        if s.contains("u-turn") { return "arrow.uturn.left" }
        if s.contains("slight left") || s.contains("bear left") { return "arrow.up.left" }
        if s.contains("slight right") || s.contains("bear right") { return "arrow.up.right" }
        if s.contains("left") { return "arrow.turn.up.left" }
        if s.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

struct DashboardView: View {
    @EnvironmentObject private var bleManager: BLEPowerMeterManager
    @EnvironmentObject private var locationManager: LocationSpeedManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var planner: RoutePlanner
    @EnvironmentObject private var health: HealthExporter
    @EnvironmentObject private var strava: StravaService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue

    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }
    @State private var finishedRide: Ride?
    @State private var showNavigationMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Connection status
                    HStack(spacing: 16) {
                        StatusDot(
                            label: bleManager.connectionState == .connected
                                ? (bleManager.connectedDeviceName ?? "Power meter")
                                : "Power meter",
                            ok: bleManager.connectionState == .connected
                        )
                        StatusDot(label: "Watch", ok: watchManager.isReachable)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    if locationManager.authorizationStatus == .denied
                        || locationManager.authorizationStatus == .restricted {
                        Text("Location access is off — speed, distance and the map need it. Enable it in Settings.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Primary live tiles
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(
                            value: bleManager.powerWatts.map { "\($0)" } ?? "--",
                            unit: "W",
                            label: "Power",
                            accent: .red
                        )
                        MetricTile(
                            value: watchManager.heartRateBpm.map { "\(Int($0.rounded()))" } ?? "--",
                            unit: "bpm",
                            label: "Heart Rate",
                            accent: .pink
                        )
                        MetricTile(
                            value: unit.speedString(mps: locationManager.speedMps),
                            unit: unit.label,
                            label: "Speed",
                            accent: .blue
                        )
                        MetricTile(
                            value: bleManager.cadenceRpm.map { String(format: "%.0f", $0) } ?? "--",
                            unit: "rpm",
                            label: "Cadence",
                            accent: .orange
                        )
                        MetricTile(
                            value: unit.distanceString(meters: locationManager.tripDistanceMeters),
                            unit: unit.distanceLabel,
                            label: "Distance",
                            accent: .green
                        )
                        MetricTile(
                            value: RideStore.formatDuration(recorder.elapsedSeconds),
                            unit: recorder.state == .paused ? "paused" : (recorder.isAutoPaused ? "auto-paused" : "active"),
                            label: "Duration",
                            accent: .purple
                        )
                    }

                    // Turn-by-turn (only while a route is active)
                    NavigationBanner(planner: planner, unit: unit, speedMps: locationManager.speedMps) {
                        showNavigationMap = true
                    }

                    // Live map (tap to go full screen)
                    Button {
                        showNavigationMap = true
                    } label: {
                        RideMapCard(recorder: recorder, planner: planner)
                            .overlay(alignment: .bottomTrailing) {
                                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.regularMaterial, in: Capsule())
                                    .padding(10)
                            }
                    }
                    .buttonStyle(.plain)

                    // Ride controls
                    rideControls
                        .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("RidePulse")
            .onReceive(locationManager.$currentLocation.compactMap { $0 }) { loc in
                planner.update(with: loc)
            }
            .onAppear {
                // Ride controls from the watch app.
                watchManager.onCommand = { command in
                    switch command {
                    case "start": if recorder.state == .idle { recorder.startRide() }
                    case "pause": recorder.pauseRide()
                    case "resume": recorder.resumeRide()
                    case "finish": finishAndSave()
                    default: break
                    }
                }
            }
            .fullScreenCover(isPresented: $showNavigationMap) {
                NavigationMapView()
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
    }

    @ViewBuilder
    private var rideControls: some View {
        switch recorder.state {
        case .idle:
            Button {
                recorder.startRide()
            } label: {
                Label("Start Ride", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        case .recording:
            HStack(spacing: 12) {
                Button {
                    recorder.pauseRide()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    finishAndSave()
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        case .paused:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        recorder.resumeRide()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        finishAndSave()
                    } label: {
                        Label("Finish", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                Button("Discard ride", role: .destructive) {
                    recorder.discardRide()
                }
                .font(.subheadline)
            }
        }
    }

    private func finishAndSave() {
        if let ride = recorder.finishRide() {
            modelContext.insert(ride)
            try? modelContext.save()
            RideExport.runAutomatic(ride, health: health, strava: strava, context: modelContext)
            finishedRide = ride   // show the post-ride summary
        }
    }
}
