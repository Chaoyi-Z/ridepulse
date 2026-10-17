import Foundation
import HealthKit
import WatchConnectivity

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

/// Runs a HealthKit cycling workout on the watch and streams live heart rate
/// to the paired iPhone via WatchConnectivity `sendMessage`.
///
/// HealthKit query handlers and WCSessionDelegate callbacks arrive on
/// background queues, so every @Published update is dispatched to main.
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var heartRateBpm: Double = 0
    @Published var isWorkoutActive: Bool = false
    @Published var authorizationStatus: String = "Not requested"
    @Published var isPhoneReachable: Bool = false
    @Published var metrics = LiveMetrics()
    private var staleTimer: Timer?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var heartRateAnchor: HKQueryAnchor?

    override init() {
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
            if m.rideState == "idle", self.session != nil, !wasIdle {
                self.stopWorkout()
            }
        }
    }

    // MARK: - HealthKit authorization

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = "Health data unavailable"
            return
        }
        let heartRate = HKQuantityType(.heartRate)
        let workout = HKWorkoutType.workoutType()
        healthStore.requestAuthorization(toShare: [workout], read: [heartRate]) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.authorizationStatus = success ? "Authorized" : "Denied"
            }
        }
    }

    // MARK: - Workout control

    func startWorkout() {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession.delegate = self
            session = workoutSession
            let startDate = Date()
            workoutSession.startActivity(with: startDate)
            startHeartRateQuery(from: startDate)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.authorizationStatus = "Workout failed to start"
            }
        }
    }

    func stopWorkout() {
        session?.end()
    }

    private func cleanup() {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        heartRateQuery = nil
        heartRateAnchor = nil
        session = nil
        isWorkoutActive = false
        heartRateBpm = 0
    }

    // MARK: - Heart rate streaming

    private func startHeartRateQuery(from startDate: Date) {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, anchor, _ in
            self?.handleHeartRateSamples(samples, anchor: anchor)
        }
        query.updateHandler = { [weak self] _, samples, _, anchor, _ in
            self?.handleHeartRateSamples(samples, anchor: anchor)
        }
        heartRateQuery = query
        healthStore.execute(query)
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?, anchor: HKQueryAnchor?) {
        if let anchor = anchor {
            heartRateAnchor = anchor
        }
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }
        let bpm = latest.quantity.doubleValue(
            for: HKUnit.count().unitDivided(by: HKUnit.minute())
        )
        DispatchQueue.main.async { [weak self] in
            self?.heartRateBpm = bpm
            self?.sendHeartRateToPhone(bpm: bpm)
        }
    }

    private func sendHeartRateToPhone(bpm: Double) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["heartRate": bpm, "timestamp": Date().timeIntervalSince1970],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isWorkoutActive = (toState == .running)
            if toState == .ended {
                self.cleanup()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.cleanup()
            self?.authorizationStatus = "Workout error"
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
