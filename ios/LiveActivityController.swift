import Foundation
import ActivityKit
import Combine

/// Starts a Live Activity when a ride begins, pushes the latest numbers to it
/// (throttled to ~2 s, or immediately when the turn instruction changes), and
/// ends it when the ride finishes or is discarded.
@MainActor
final class LiveActivityController: ObservableObject {
    private let recorder: RideRecorder
    private let location: LocationSpeedManager
    private let ble: BLEPowerMeterManager
    private let watch: WatchConnectivityManager
    private let planner: RoutePlanner

    private var activity: Activity<RideActivityAttributes>?
    private var cancellables = Set<AnyCancellable>()
    private var lastUpdate = Date.distantPast
    private var lastInstruction: String?

    init(recorder: RideRecorder, location: LocationSpeedManager, ble: BLEPowerMeterManager,
         watch: WatchConnectivityManager, planner: RoutePlanner) {
        self.recorder = recorder
        self.location = location
        self.ble = ble
        self.watch = watch
        self.planner = planner

        recorder.$state
            .removeDuplicates()
            .sink { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .recording where self?.activity == nil: self?.start()
                    case .idle: self?.end(); self?.push(force: true)
                    default: self?.push(force: true)
                    }
                }
            }
            .store(in: &cancellables)

        // Ticks once a second while recording; location fires on every GPS fix.
        recorder.$elapsedSeconds
            .merge(with: location.$currentLocation.map { _ in 0 })
            .sink { [weak self] _ in Task { @MainActor in self?.push(force: false) } }
            .store(in: &cancellables)

        planner.$progress
            .map { $0?.nextInstruction }
            .removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.push(force: true) } }
            .store(in: &cancellables)
    }

    private var useMetric: Bool {
        SpeedUnit.fromStored(UserDefaults.standard.string(forKey: "speedUnit") ?? SpeedUnit.mph.rawValue) == .kmh
    }

    private func currentState() -> RideActivityAttributes.ContentState {
        let hr: Int? = {
            guard let bpm = watch.heartRateBpm, let d = watch.lastHeartRateDate,
                  Date().timeIntervalSince(d) < 15 else { return nil }
            return Int(bpm.rounded())
        }()
        let rideState: String = recorder.state == .paused ? "paused" : (recorder.isAutoPaused ? "auto" : "recording")
        return RideActivityAttributes.ContentState(
            speedMps: location.speedMps,
            powerWatts: ble.powerWatts,
            heartRateBpm: hr,
            distanceMeters: location.tripDistanceMeters,
            elapsedSeconds: recorder.elapsedSeconds,
            rideState: rideState,
            nextInstruction: planner.progress?.nextInstruction,
            distanceToManeuverMeters: planner.progress?.distanceToManeuverMeters,
            remainingMeters: planner.progress?.remainingMeters,
            useMetric: useMetric
        )
    }

    private func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RideActivityAttributes(startDate: Date(), routeName: planner.activeRoute?.name)
        let content = ActivityContent(state: currentState(), staleDate: Date().addingTimeInterval(60))
        activity = try? Activity.request(attributes: attrs, content: content, pushType: nil)
        lastUpdate = Date()
    }

    private func push(force: Bool) {
        let state = currentState()
        broadcastToWatch(state, force: force)
        guard let activity else { return }
        if !force, Date().timeIntervalSince(lastUpdate) < 2 { return }
        lastUpdate = Date()
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
        Task { await activity.update(content) }
    }

    /// Mirror the same numbers to the watch so it can act as a bike computer.
    private func broadcastToWatch(_ s: RideActivityAttributes.ContentState, force: Bool) {
        var m: [String: Any] = [
            "speedMps": s.speedMps,
            "distanceMeters": s.distanceMeters,
            "elapsedSeconds": s.elapsedSeconds,
            "rideState": recorder.state == .idle ? "idle" : s.rideState,
            "useMetric": s.useMetric
        ]
        if let p = s.powerWatts { m["powerWatts"] = p }
        if let c = ble.cadenceRpm { m["cadenceRpm"] = c }
        if let i = s.nextInstruction { m["nextInstruction"] = i }
        if let d = s.distanceToManeuverMeters { m["distanceToManeuver"] = d }
        watch.sendLiveMetrics(m, force: force)
    }

    private func end() {
        guard let activity else { return }
        let content = ActivityContent(state: currentState(), staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
