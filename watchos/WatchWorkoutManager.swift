import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// Latest numbers mirrored from the iPhone.
struct LiveMetrics {
    var speedMps: Double = 0
    var powerWatts: Int?
    var cadenceRpm: Double?
    var distanceMeters: Double = 0
    var elapsedSeconds: Double = 0
    var rideState: String = ""
    var nextInstruction: String?
    var distanceToManeuver: Double?
    var useMetric = false
    var receivedAt: Date = .distantPast
    var isStale: Bool { Date().timeIntervalSince(receivedAt) > 20 }

    init() {}
    init(_ d: [String: Any]) {
        speedMps = d["speedMps"] as? Double ?? 0
        powerWatts = d["powerWatts"] as? Int
        cadenceRpm = d["cadenceRpm"] as? Double
        distanceMeters = d["distanceMeters"] as? Double ?? 0
        elapsedSeconds = d["elapsedSeconds"] as? Double ?? 0
        rideState = d["rideState"] as? String ?? ""
        nextInstruction = d["nextInstruction"] as? String
        distanceToManeuver = d["distanceToManeuver"] as? Double
        useMetric = d["useMetric"] as? Bool ?? false
        receivedAt = Date()
    }
}

/// Runs a HealthKit cycling workout on the watch with a live workout builder
/// (which makes the watch sample heart rate every second) and streams the live
/// heart rate to the paired iPhone via WatchConnectivity.
///
/// The workout is started either by the user on the watch, automatically when
/// the phone's ride starts, or remotely: the iPhone calls
/// `HKHealthStore.startWatchApp(with:)`, which launches this app and calls
/// `WatchAppDelegate.handle(_:)`. The watch workout is *discarded* when it ends —
/// the iPhone saves the single combined workout to Health, so there are no duplicates.
///
/// HealthKit and WCSession callbacks arrive on background queues, so every
/// @Published update is dispatched to main.
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published var heartRateBpm: Double = 0
    @Published var isWorkoutActive: Bool = false
    @Published var authorizationStatus: String = "Not requested"
    @Published var isPhoneReachable: Bool = false
    @Published var metrics = LiveMetrics()
    /// Recent diagnostic lines (also printed, and shown on the watch HR page).
    @Published var log: [String] = []
    private var staleTimer: Timer?

    /// Tell the iPhone what went wrong so it can show it on the Ride/Devices screens.
    func reportStatus(_ text: String) {
        note(text)
        DispatchQueue.main.async { [weak self] in self?.authorizationStatus = text }
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["watchStatus": text], replyHandler: nil, errorHandler: nil)
    }

    static let permissionHelp = "Health access is OFF. On iPhone: Health app > profile picture > Apps > RidePulse > Turn On All."

    func note(_ text: String) {
        print("[RidePulseWatch] \(text)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.log.append(text)
            if self.log.count > 8 { self.log.removeFirst(self.log.count - 8) }
        }
    }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        // Re-render periodically so "stale" state and the clock stay honest.
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Commands to the phone

    func sendCommand(_ command: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["command": command], replyHandler: nil, errorHandler: nil)
    }

    private func handleIncoming(_ d: [String: Any]) {
        if let workout = d["workout"] as? String {
            DispatchQueue.main.async { [weak self] in
                if workout == "stop" { self?.stopWorkout() }
                if workout == "start" { self?.startWorkout() }
            }
            return
        }
        guard d["kind"] as? String == "metrics" else { return }
        let m = LiveMetrics(d)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wasIdle = self.metrics.rideState == "idle" || self.metrics.rideState.isEmpty
            self.metrics = m
            // Ride started on the phone → start streaming HR without touching the watch.
            if wasIdle, m.rideState == "recording", self.session == nil {
                self.startWorkout()
            }
            // Ride finished/discarded on the phone → stop the workout.
            if m.rideState == "idle", self.session != nil, !wasIdle {
                self.stopWorkout()
            }
        }
    }

    // MARK: - HealthKit authorization

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = "Health data unavailable"
            completion?(false)
            return
        }
        let heartRate = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        let workout = HKWorkoutType.workoutType()
        note("requesting Health authorization")
        healthStore.requestAuthorization(toShare: [workout, heartRate, energy], read: [heartRate]) { [weak self] success, error in
            let shareStatus = self?.healthStore.authorizationStatus(for: workout).rawValue ?? -1
            self?.note("authorization finished: success=\(success) workoutShareStatus=\(shareStatus) error=\(error?.localizedDescription ?? "none")")
            DispatchQueue.main.async {
                // HKAuthorizationStatus: 0 not determined, 1 denied, 2 authorized.
                if shareStatus == HKAuthorizationStatus.sharingDenied.rawValue {
                    self?.reportStatus(Self.permissionHelp)
                } else {
                    self?.authorizationStatus = success ? "Authorized" : "Denied"
                }
                completion?(success)
            }
        }
    }

    // MARK: - Workout control

    /// Start a workout. `configuration` is supplied when the iPhone launches us.
    func startWorkout(configuration: HKWorkoutConfiguration? = nil) {
        guard session == nil else { note("startWorkout ignored: session already exists"); return }
        note("startWorkout called")
        let config: HKWorkoutConfiguration
        if let configuration {
            config = configuration
        } else {
            config = HKWorkoutConfiguration()
            config.activityType = .cycling
            config.locationType = .outdoor
        }

        do {
            let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            workoutSession.delegate = self
            workoutBuilder.delegate = self
            session = workoutSession
            builder = workoutBuilder

            let start = Date()
            workoutSession.startActivity(with: start)
            note("session.startActivity called, state=\(workoutSession.state.rawValue)")
            workoutBuilder.beginCollection(withStart: start) { [weak self] success, error in
                self?.note("beginCollection success=\(success) error=\(error?.localizedDescription ?? "none")")
                if !success {
                    let denied = (error?.localizedDescription ?? "").localizedCaseInsensitiveContains("authorized")
                    self?.reportStatus(denied ? Self.permissionHelp
                                              : "Collection failed: \(error?.localizedDescription ?? "unknown")")
                    // A session with no data collection is useless and drains battery.
                    DispatchQueue.main.async { self?.stopWorkout() }
                }
            }
        } catch {
            note("HKWorkoutSession init FAILED: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.authorizationStatus = "Workout failed to start: \(error.localizedDescription)"
            }
        }
    }

    func stopWorkout() {
        session?.end()
    }

    private func finishAndDiscard() {
        let b = builder
        builder = nil
        session = nil
        isWorkoutActive = false
        heartRateBpm = 0
        b?.endCollection(withEnd: Date()) { _, _ in
            // The iPhone saves the combined ride to Health; don't duplicate it from here.
            b?.discardWorkout()
        }
    }

    // MARK: - Heart rate streaming

    private func sendHeartRateToPhone(bpm: Double) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["heartRate": bpm, "timestamp": Date().timeIntervalSince1970],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        note("builder collected: \(collectedTypes.map { $0.identifier.replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "") }.joined(separator: ","))")
        guard collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let quantity = stats.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        DispatchQueue.main.async { [weak self] in
            self?.heartRateBpm = bpm
            self?.sendHeartRateToPhone(bpm: bpm)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        note("session state \(fromState.rawValue) -> \(toState.rawValue)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isWorkoutActive = (toState == .running)
            if toState == .ended {
                self.finishAndDiscard()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        note("session FAILED: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.finishAndDiscard()
            self?.authorizationStatus = "Workout error: \(error.localizedDescription)"
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchWorkoutManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isPhoneReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isPhoneReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncoming(applicationContext)
    }

    // sessionDidBecomeInactive/DidDeactivate are iOS-only and unavailable on watchOS.
}

// MARK: - Launch from the iPhone

/// `HKHealthStore.startWatchApp(with:)` on the phone launches this app and calls
/// `handle(_:)` — that is how a ride started on the iPhone starts the watch workout
/// even when the watch app isn't open.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let manager = WatchWorkoutManager.shared
        manager.note("handle(workoutConfiguration) from iPhone")
        manager.requestAuthorization { _ in
            manager.startWorkout(configuration: workoutConfiguration)
        }
    }
}
