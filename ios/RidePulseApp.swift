import SwiftUI
import SwiftData

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
                .onChange(of: scenePhase) { _, phase in
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
}
