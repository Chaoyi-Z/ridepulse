import Foundation
import CoreLocation

/// Ride recording state machine.
enum RideState {
    case idle
    case recording
    case paused
}

/// Records 1-second samples while a ride is active and builds a `Ride` on finish.
/// Samples stay in memory until `finishRide()`; the caller inserts the returned
/// Ride into SwiftData (inserting the ride inserts its samples via cascade).
final class RideRecorder: ObservableObject {
    @Published var state: RideState = .idle
    /// Active (unpaused) elapsed seconds, updated live by the 1s timer.
    @Published var elapsedSeconds: TimeInterval = 0
    /// GPS coordinates captured during this ride, for the live route polyline.
    @Published var liveCoordinates: [CLLocationCoordinate2D] = []
    @Published var sampleCount: Int = 0
    /// True while the ride is recording but auto-paused because the rider is stopped.
    @Published var isAutoPaused: Bool = false

    static let autoPauseKey = "autoPause"
    private var autoPauseEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoPauseKey) as? Bool ?? true
    }
    private let autoPauseBelowMps = 0.9   // ~2 mph
    private let autoResumeAboveMps = 1.6  // ~3.5 mph
    private var stoppedSeconds = 0
    private var autoPauseStart: Date?

    private let powerManager: BLEPowerMeterManager
    private let locationManager: LocationSpeedManager
    private let watchManager: WatchConnectivityManager

    private var timer: Timer?
    private var samples: [RideSample] = []
    private var rideStartDate = Date()
    private var pausedTotal: TimeInterval = 0
    private var pauseStart: Date?
    private var maxSpeed: Double = 0

    init(
        powerManager: BLEPowerMeterManager,
        locationManager: LocationSpeedManager,
        watchManager: WatchConnectivityManager
    ) {
        self.powerManager = powerManager
        self.locationManager = locationManager
        self.watchManager = watchManager
    }

    // MARK: - Control

    func startRide() {
        guard state == .idle else { return }
        samples = []
        rideStartDate = Date()
        pausedTotal = 0
        pauseStart = nil
        elapsedSeconds = 0
        liveCoordinates = []
        sampleCount = 0
        maxSpeed = 0
        stoppedSeconds = 0
        autoPauseStart = nil
        isAutoPaused = false
        locationManager.resetTripDistance()
        locationManager.startUpdates()
        watchManager.launchWatchWorkout()
        state = .recording
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func pauseRide() {
        guard state == .recording else { return }
        endAutoPause()
        pauseStart = Date()
        state = .paused
    }

    /// Fold an in-progress auto-pause into `pausedTotal`.
    private func endAutoPause() {
        if let start = autoPauseStart {
            pausedTotal += Date().timeIntervalSince(start)
        }
        autoPauseStart = nil
        stoppedSeconds = 0
        isAutoPaused = false
    }

    func resumeRide() {
        guard state == .paused else { return }
        if let pauseStart = pauseStart {
            pausedTotal += Date().timeIntervalSince(pauseStart)
        }
        pauseStart = nil
        state = .recording
    }

    func discardRide() {
        timer?.invalidate()
        timer = nil
        samples = []
        liveCoordinates = []
        state = .idle
        // GPS keeps running for navigation/live speed; the App stops it on background when idle.
    }

    /// Ends the ride and returns an unsaved Ride. Caller inserts into SwiftData.
    func finishRide() -> Ride? {
        guard state != .idle else { return nil }
        timer?.invalidate()
        timer = nil
        endAutoPause()
        if state == .paused, let pauseStart { pausedTotal += Date().timeIntervalSince(pauseStart) }
        let endDate = Date()
        let distance = locationManager.tripDistanceMeters
        let elapsed = Date().timeIntervalSince(rideStartDate) - pausedTotal
        elapsedSeconds = elapsed

        let powers = samples.compactMap { $0.powerWatts }
        let heartRates = samples.compactMap { $0.heartRateBpm }

        let ride = Ride(
            startDate: rideStartDate,
            endDate: endDate,
            distanceMeters: distance,
            durationSeconds: elapsed,
            avgPowerWatts: powers.isEmpty ? 0 : Double(powers.reduce(0, +)) / Double(powers.count),
            maxPowerWatts: powers.max() ?? 0,
            avgHeartRate: heartRates.isEmpty ? 0 : Double(heartRates.reduce(0, +)) / Double(heartRates.count),
            maxHeartRate: heartRates.max() ?? 0,
            avgSpeedMps: elapsed > 0 ? distance / elapsed : 0,
            maxSpeedMps: maxSpeed
        )
        ride.samples = samples
        for sample in samples {
            sample.ride = ride
        }

        samples = []
        liveCoordinates = []
        state = .idle
        // GPS keeps running for navigation/live speed; the App stops it on background when idle.
        return ride
    }

    // MARK: - Sampling

    private func tick() {
        guard state == .recording else { return }

        // Auto-pause: stop the clock (and sampling) while the rider is stationary,
        // e.g. at traffic lights, so moving time and averages stay honest.
        let currentSpeed = locationManager.speedMps
        if autoPauseEnabled {
            if isAutoPaused {
                if currentSpeed >= autoResumeAboveMps { endAutoPause() }
            } else if currentSpeed < autoPauseBelowMps {
                stoppedSeconds += 1
                if stoppedSeconds >= 3 {
                    isAutoPaused = true
                    autoPauseStart = Date()
                }
            } else {
                stoppedSeconds = 0
            }
        } else if isAutoPaused {
            endAutoPause()
        }
        if isAutoPaused { return }

        elapsedSeconds = Date().timeIntervalSince(rideStartDate) - pausedTotal

        // Treat watch HR as stale after 15 s without an update.
        let heartRate: Int? = {
            guard let bpm = watchManager.heartRateBpm,
                  let date = watchManager.lastHeartRateDate,
                  Date().timeIntervalSince(date) < 15 else { return nil }
            return Int(bpm.rounded())
        }()

        let speed = locationManager.speedMps
        maxSpeed = max(maxSpeed, speed)

        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        if let loc = locationManager.currentLocation,
           loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 {
            latitude = loc.coordinate.latitude
            longitude = loc.coordinate.longitude
            altitude = loc.altitude
            liveCoordinates.append(loc.coordinate)
        }

        let sample = RideSample(
            timestamp: Date(),
            powerWatts: powerManager.powerWatts,
            heartRateBpm: heartRate,
            speedMps: speed,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude
        )
        samples.append(sample)
        sampleCount = samples.count
    }
}
