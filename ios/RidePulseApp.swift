import SwiftUI
import SwiftData
import UIKit

@main
struct RidePulseApp: App {
    @StateObject private var bleManager: BLEPowerMeterManager
    @StateObject private var locationManager: LocationSpeedManager
    @StateObject private var watchManager: WatchConnectivityManager
    @StateObject private var recorder: RideRecorder
    @StateObject private var planner: RoutePlanner
    @StateObject private var liveActivity: LiveActivityController
    @StateObject private var health = HealthExporter()
    @StateObject private var strava = StravaService()
    @Environment(\.scenePhase) private var scenePhase
    /// Keep the screen on while recording a ride or following a route.
    @AppStorage("keepAwakeRide") private var keepAwakeRide = true
    /// Keep the screen on whenever RidePulse is open in the foreground.
    @AppStorage("keepAwakeAlways") private var keepAwakeAlways = false

    init() {
        let ble = BLEPowerMeterManager()
        let location = LocationSpeedManager()
        let watch = WatchConnectivityManager()
        let planner = RoutePlanner()
        let recorder = RideRecorder(powerManager: ble, locationManager: location, watchManager: watch)
        _bleManager = StateObject(wrappedValue: ble)
        _locationManager = StateObject(wrappedValue: location)
        _watchManager = StateObject(wrappedValue: watch)
        _recorder = StateObject(wrappedValue: recorder)
        _planner = StateObject(wrappedValue: planner)
        _liveActivity = StateObject(wrappedValue: LiveActivityController(
            recorder: recorder, location: location, ble: ble, watch: watch, planner: planner
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(locationManager)
                .environmentObject(watchManager)
                .environmentObject(recorder)
                .environmentObject(planner)
                .environmentObject(health)
                .environmentObject(strava)
                .onAppear {
                    locationManager.requestPermission()
                    // Navigation needs continuous fixes even before a ride starts.
                    locationManager.startUpdates()
                }
                .onChange(of: recorder.state) { _, _ in updateScreenAwake() }
                .onChange(of: planner.activeRoute?.name) { _, _ in updateScreenAwake() }
                .onChange(of: keepAwakeRide) { _, _ in updateScreenAwake() }
                .onChange(of: keepAwakeAlways) { _, _ in updateScreenAwake() }
                .onChange(of: scenePhase) { _, phase in
                    updateScreenAwake()
                    // Save battery: only keep GPS running in the background while
                    // recording a ride or following a route.
                    switch phase {
                    case .active:
                        locationManager.startUpdates()
                    case .background:
                        if recorder.state == .idle && planner.activeRoute == nil {
                            locationManager.stopUpdates()
                        }
                    default:
                        break
                    }
                }
        }
        .modelContainer(for: [Ride.self, RideSample.self, SavedRoute.self])
    }

    /// The idle timer only matters in the foreground; iOS ignores it otherwise.
    private func updateScreenAwake() {
        let riding = recorder.state != .idle || planner.activeRoute != nil
        UIApplication.shared.isIdleTimerDisabled =
            scenePhase == .active && (keepAwakeAlways || (keepAwakeRide && riding))
    }
}
