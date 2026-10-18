import Foundation
import WatchConnectivity
import HealthKit

/// iOS side of the phone<->watch link. Receives live heart rate sent by the
/// watch app via `WCSession.sendMessage`.
///
/// WCSessionDelegate callbacks arrive on a background queue, so every
/// @Published update is dispatched to the main queue.
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published var heartRateBpm: Double?
    @Published var lastHeartRateDate: Date?
    @Published var isReachable: Bool = false
    @Published var isPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    /// Ride control requested from the watch: "start" | "pause" | "resume" | "finish".
    var onCommand: ((String) -> Void)?
    private var lastMetricsSent = Date.distantPast
    /// Result of the last attempt to launch the watch app / workout, for the Devices screen.
    @Published var watchLaunchStatus: String?
    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            // Delegate must be set BEFORE activate().
            session.delegate = self
            session.activate()
        }
    }
}

// MARK: - Launch the watch workout from the phone

extension WatchConnectivityManager {
    /// Ask the watch to start a cycling workout (launching the watch app if it
    /// isn't open). This is what makes heart rate flow when a ride is started
    /// from the iPhone without touching the watch.
    func launchWatchWorkout() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        // startWatchApp needs the app to be authorized to share workouts.
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { [weak self] _, _ in
            self?.healthStore.startWatchApp(with: config) { success, error in
                DispatchQueue.main.async {
                    self?.watchLaunchStatus = success
                        ? "Asked the watch to start its workout."
                        : "Couldn't start the watch app: \(error?.localizedDescription ?? "unknown error")"
                }
            }
        }
    }
}

extension WatchConnectivityManager {
    /// Ask the watch to end its heart-rate workout (needs the watch to be reachable).
    func stopWatchWorkout() {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            watchLaunchStatus = "Watch not reachable — end the workout on the watch."
            return
        }
        WCSession.default.sendMessage(["workout": "stop"], replyHandler: nil, errorHandler: nil)
        watchLaunchStatus = "Asked the watch to stop its workout."
    }
}

// MARK: - Live metrics to the watch

extension WatchConnectivityManager {
    /// Push the current numbers to the watch (≤ 1/s). Uses the low-latency
    /// message channel when the watch app is in front, otherwise application
    /// context so the watch gets the latest values when it wakes.
    func sendLiveMetrics(_ metrics: [String: Any], force: Bool = false) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        if !force, Date().timeIntervalSince(lastMetricsSent) < 1.0 { return }
        lastMetricsSent = Date()
        var payload = metrics
        payload["kind"] = "metrics"
        payload["timestamp"] = Date().timeIntervalSince1970
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let status = message["watchStatus"] as? String {
            DispatchQueue.main.async { [weak self] in self?.watchLaunchStatus = status }
            return
        }
        if let command = message["command"] as? String {
            DispatchQueue.main.async { [weak self] in self?.onCommand?(command) }
            return
        }
        guard let bpm = message["heartRate"] as? Double,
              let ts = message["timestamp"] as? Double else { return }
        DispatchQueue.main.async { [weak self] in
            self?.heartRateBpm = bpm
            self?.lastHeartRateDate = Date(timeIntervalSince1970: ts)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
        }
    }

    // Required iOS stubs (only called on iOS).
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
}
