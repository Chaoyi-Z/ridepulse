import Foundation
import SwiftData

/// A completed (or in-progress, transient) cycling ride.
@Model
final class Ride {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    var distanceMeters: Double = 0
    var durationSeconds: Double = 0
    var avgPowerWatts: Double = 0
    var maxPowerWatts: Int = 0
    var avgHeartRate: Double = 0
    var maxHeartRate: Int = 0
    var avgSpeedMps: Double = 0
    var maxSpeedMps: Double = 0
    /// Set once the ride has been written to Apple Health / uploaded to Strava.
    var healthWorkoutUUID: String?
    var stravaActivityID: Int?

    @Relationship(deleteRule: .cascade, inverse: \RideSample.ride)
    var samples: [RideSample] = []

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date = Date(),
        distanceMeters: Double = 0,
        durationSeconds: Double = 0,
        avgPowerWatts: Double = 0,
        maxPowerWatts: Int = 0,
        avgHeartRate: Double = 0,
        maxHeartRate: Int = 0,
        avgSpeedMps: Double = 0,
        maxSpeedMps: Double = 0
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.avgPowerWatts = avgPowerWatts
        self.maxPowerWatts = maxPowerWatts
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.avgSpeedMps = avgSpeedMps
        self.maxSpeedMps = maxSpeedMps
    }
}

/// One 1-second sample captured during a ride. Samples are created transiently
/// by RideRecorder and inserted into SwiftData only when the ride finishes.
@Model
final class RideSample {
    var timestamp: Date = Date()
    var powerWatts: Int?
    var heartRateBpm: Int?
    var speedMps: Double = 0
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?

    var ride: Ride?

    init(
        timestamp: Date = Date(),
        powerWatts: Int? = nil,
        heartRateBpm: Int? = nil,
        speedMps: Double = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil
    ) {
        self.timestamp = timestamp
        self.powerWatts = powerWatts
        self.heartRateBpm = heartRateBpm
        self.speedMps = speedMps
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}
