import Foundation
import HealthKit
import CoreLocation

/// Saves a finished ride to Apple Health as an outdoor cycling workout with
/// distance, energy, heart rate, power samples and the GPS route. The watch app
/// only runs a session for live HR (it never writes a workout), so this is the
/// single record that shows up in Fitness.
@MainActor
final class HealthExporter: ObservableObject {
    static let enabledKey = "saveToHealth"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    @Published private(set) var lastMessage: String?

    private let store = HKHealthStore()

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate)
        ]
        types.insert(HKQuantityType(.cyclingPower))
        types.insert(HKQuantityType(.cyclingSpeed))
        return types
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
            return true
        } catch {
            lastMessage = "Health access failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Save the ride. Returns the workout UUID on success.
    func save(_ ride: Ride) async -> UUID? {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastMessage = "Health data not available on this device."
            return nil
        }
        guard await requestAuthorization() else { return nil }

        let samples = ride.samples.sorted { $0.timestamp < $1.timestamp }
        let start = ride.startDate
        let end = max(ride.endDate, start.addingTimeInterval(1))

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: start)

            var hkSamples: [HKSample] = []

            // Distance as one sample over the whole ride.
            if ride.distanceMeters > 0 {
                hkSamples.append(HKQuantitySample(
                    type: HKQuantityType(.distanceCycling),
                    quantity: HKQuantity(unit: .meter(), doubleValue: ride.distanceMeters),
                    start: start, end: end))
            }

            // Energy: kJ ≈ kcal for cycling when we have power; otherwise skip.
            let stats = RideStats(ride: ride, ftp: nil, maxHR: nil)
            if let kcal = stats.estimatedCalories, kcal > 0 {
                hkSamples.append(HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: start, end: end))
            }

            // Per-second HR and power (thin to every 5 s to keep the write small).
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            var i = 0
            while i < samples.count {
                let s = samples[i]
                let next = min(i + 5, samples.count - 1)
                let sEnd = max(samples[next].timestamp, s.timestamp.addingTimeInterval(1))
                if let hr = s.heartRateBpm, hr > 0 {
                    hkSamples.append(HKQuantitySample(
                        type: HKQuantityType(.heartRate),
                        quantity: HKQuantity(unit: bpmUnit, doubleValue: Double(hr)),
                        start: s.timestamp, end: s.timestamp))
                }
                if let p = s.powerWatts {
                    hkSamples.append(HKQuantitySample(
                        type: HKQuantityType(.cyclingPower),
                        quantity: HKQuantity(unit: .watt(), doubleValue: Double(p)),
                        start: s.timestamp, end: sEnd))
                }
                i += 5
            }
            if !hkSamples.isEmpty {
                try await builder.addSamples(hkSamples)
            }

            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: false,
                HKMetadataKeyWorkoutBrandName: "RidePulse"
            ])
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                lastMessage = "Health didn't return a workout."
                return nil
            }

            // GPS route
            let locations: [CLLocation] = samples.compactMap { s in
                guard let lat = s.latitude, let lon = s.longitude else { return nil }
                return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                  altitude: s.altitude ?? 0, horizontalAccuracy: 10, verticalAccuracy: 10,
                                  course: -1, speed: s.speedMps, timestamp: s.timestamp)
            }
            if locations.count > 1 {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try await routeBuilder.insertRouteData(locations)
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }

            lastMessage = "Saved to Apple Health."
            return workout.uuid
        } catch {
            lastMessage = "Health save failed: \(error.localizedDescription)"
            return nil
        }
    }
}
