import Foundation
import CoreLocation

/// GPS location + speed. Created on the main thread; CLLocationManager delegate
/// callbacks arrive on the creating thread (main), so @Published updates are safe.
///
/// Distance accumulates into `tripDistanceMeters` between `resetTripDistance()`
/// calls; RideRecorder resets it at ride start, so it reflects ride distance.
final class LocationSpeedManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var speedMps: Double = 0
    @Published var currentLocation: CLLocation?
    @Published var tripDistanceMeters: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var lastLocationForDistance: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        // Takes effect once authorized; requires the "location" UIBackgroundMode.
        manager.allowsBackgroundLocationUpdates = true
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Ask for Always authorization so background tracking keeps working.
    /// Call only after WhenInUse is granted; the system may prompt the user.
    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    private var wantsUpdates = false

    func startUpdates() {
        wantsUpdates = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
    }

    func resetTripDistance() {
        tripDistanceMeters = 0
        lastLocationForDistance = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        currentLocation = loc
        // CLLocation.speed is -1 when invalid.
        speedMps = loc.speed >= 0 ? loc.speed : 0

        // Accumulate distance only on reasonably accurate fixes, with a spike guard.
        if loc.horizontalAccuracy < 50 {
            if let prev = lastLocationForDistance {
                let delta = loc.distance(from: prev)
                if delta < 200 {
                    tripDistanceMeters += delta
                }
            }
            lastLocationForDistance = loc
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // If updates were requested before the user answered the permission
        // prompt, (re)start them now that we're authorized.
        if wantsUpdates,
           authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep last known values; nothing fatal to surface in v1.
    }
}
