import Foundation
import WatchConnectivity

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
