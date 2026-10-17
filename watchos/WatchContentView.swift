import SwiftUI

/// Two pages: a bike computer mirroring the phone's live numbers (with ride
/// controls), and the heart-rate workout page.
struct WatchContentView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        TabView {
            BikeComputerPage()
            HeartRatePage()
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            workoutManager.requestAuthorization()
        }
    }
}

// MARK: - Page 1: bike computer

struct BikeComputerPage: View {
    @EnvironmentObject private var wm: WatchWorkoutManager

    private var m: LiveMetrics { wm.metrics }
    private var metric: Bool { m.useMetric }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                // Phone link + state
                HStack(spacing: 4) {
                    Circle().fill(wm.isPhoneReachable ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(stateLabel).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }

                if m.isStale {
                    Text("Open RidePulse on iPhone")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    // Speed hero
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(fmtSpeed(m.speedMps))
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.blue)
                        Text(metric ? "km/h" : "mph").font(.caption2).foregroundStyle(.secondary)
                    }

                    // 2×2 grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        tile(m.powerWatts.map { "\($0)" } ?? "--", "W", .red)
                        tile(wm.isWorkoutActive && wm.heartRateBpm > 0 ? "\(Int(wm.heartRateBpm))" : "--", "bpm", .pink)
                        tile(fmtDistance(m.distanceMeters), metric ? "km" : "mi", .green)
                        tile(fmtDuration(m.elapsedSeconds), m.rideState == "auto" ? "auto" : "", .purple)
                    }

                    if let instr = m.nextInstruction {
                        HStack(spacing: 4) {
                            Image(systemName: maneuverSymbol(instr)).font(.caption.bold())
                            if let d = m.distanceToManeuver { Text(fmtShort(d)).font(.caption.bold().monospacedDigit()) }
                            Text(instr).font(.caption2).lineLimit(1)
                        }
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                controls
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch m.rideState {
        case "idle", "":
            Button { wm.sendCommand("start") } label: {
                Label("Start Ride", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.green)
        case "paused":
            HStack {
                Button { wm.sendCommand("resume") } label: { Image(systemName: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button { wm.sendCommand("finish") } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        default: // recording / auto
            HStack {
                Button { wm.sendCommand("pause") } label: { Image(systemName: "pause.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.orange)
                Button { wm.sendCommand("finish") } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }

    private var stateLabel: String {
        switch m.rideState {
        case "recording": return "Recording"
        case "paused": return "Paused"
        case "auto": return "Auto-paused"
        default: return wm.isPhoneReachable ? "Ready" : "Phone not reachable"
        }
    }

    private func tile(_ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fmtSpeed(_ mps: Double) -> String { String(format: "%.1f", metric ? mps * 3.6 : mps * 2.23694) }
    private func fmtDistance(_ m: Double) -> String { String(format: "%.2f", metric ? m / 1000 : m / 1609.344) }
    private func fmtShort(_ m: Double) -> String {
        if metric { return m >= 950 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m" }
        let ft = m * 3.28084
        return ft >= 900 ? String(format: "%.1f mi", ft / 5280) : "\(Int((ft / 10).rounded() * 10)) ft"
    }
    private func fmtDuration(_ s: Double) -> String {
        let t = Int(s.rounded()); let h = t / 3600, mm = (t % 3600) / 60, ss = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, mm, ss) : String(format: "%d:%02d", mm, ss)
    }
    private func maneuverSymbol(_ i: String) -> String {
        let s = i.lowercased()
        if s.contains("arrive") { return "flag.checkered" }
        if s.contains("u-turn") { return "arrow.uturn.left" }
        if s.contains("slight left") { return "arrow.up.left" }
        if s.contains("slight right") { return "arrow.up.right" }
        if s.contains("left") { return "arrow.turn.up.left" }
        if s.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

// MARK: - Page 2: heart-rate workout

struct HeartRatePage: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(workoutManager.isPhoneReachable ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(workoutManager.isPhoneReachable ? "Phone linked" : "Phone not reachable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if workoutManager.isWorkoutActive {
                Text("\(Int(workoutManager.heartRateBpm))")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.pink)
                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "heart.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.pink)
                Text(workoutManager.authorizationStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Starts automatically with a ride")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if workoutManager.isWorkoutActive {
                    workoutManager.stopWorkout()
                } else {
                    workoutManager.startWorkout()
                }
            } label: {
                Text(workoutManager.isWorkoutActive ? "End HR Workout" : "Start HR Workout")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(workoutManager.isWorkoutActive ? .red : .green)
        }
        .padding()
    }
}
