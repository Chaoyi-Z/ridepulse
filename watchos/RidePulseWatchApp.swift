import SwiftUI

@main
struct RidePulseWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var workoutManager = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workoutManager)
                .onAppear {
                    // Debug hook: `devicectl ... --environment-variables '{"RP_AUTOSTART":"1"}'`
                    if ProcessInfo.processInfo.environment["RP_AUTOSTART"] == "1" {
                        workoutManager.requestAuthorization { _ in workoutManager.startWorkout() }
                    }
                }
        }
    }
}
