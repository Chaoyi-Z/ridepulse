import Foundation
import SwiftData

/// Post-ride automation: save to Apple Health and (optionally) upload to
/// Strava without blocking the summary sheet.
enum RideExport {
    @MainActor
    static func runAutomatic(_ ride: Ride, health: HealthExporter, strava: StravaService, context: ModelContext) {
        // Nothing to export for a ride with no GPS fixes (e.g. an accidental tap).
        guard ride.samples.contains(where: { $0.latitude != nil }) || ride.durationSeconds > 60 else { return }
        Task { @MainActor in
            if HealthExporter.isEnabled, ride.healthWorkoutUUID == nil {
                if let id = await health.save(ride) {
                    ride.healthWorkoutUUID = id.uuidString
                    try? context.save()
                }
            }
            if StravaService.isAutoUploadEnabled, strava.isConnected, ride.stravaActivityID == nil {
                if let id = try? await strava.upload(ride, name: "Ride · \(RideStore.formatDate(ride.startDate))") {
                    ride.stravaActivityID = id
                    try? context.save()
                }
            }
        }
    }
}
