import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen banner + Dynamic Island for an in-progress ride.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenRideView(context: context)
                .activityBackgroundTint(Color(red: 0.05, green: 0.10, blue: 0.21))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    stat(RideActivityFormat.speed(s.speedMps, metric: s.useMetric),
                         RideActivityFormat.speedUnit(metric: s.useMetric), .blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    stat(s.powerWatts.map { "\($0)" } ?? "--", "W", .red)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(RideActivityFormat.duration(s.elapsedSeconds))
                            .font(.title2.bold().monospacedDigit())
                        Text("\(RideActivityFormat.distance(s.distanceMeters, metric: s.useMetric)) \(RideActivityFormat.distanceUnit(metric: s.useMetric))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let instr = s.nextInstruction {
                        HStack(spacing: 8) {
                            Image(systemName: maneuverSymbol(instr)).font(.title3.bold())
                            if let d = s.distanceToManeuverMeters {
                                Text(RideActivityFormat.shortDistance(d, metric: s.useMetric))
                                    .font(.headline.monospacedDigit())
                            }
                            Text(instr).font(.subheadline).lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(.green)
                    } else if let hr = s.heartRateBpm {
                        Label("\(hr) bpm", systemImage: "heart.fill").foregroundStyle(.pink).font(.subheadline)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "bicycle").font(.caption2)
                    Text(RideActivityFormat.speed(s.speedMps, metric: s.useMetric))
                        .font(.caption.bold().monospacedDigit())
                }
                .foregroundStyle(.blue)
            } compactTrailing: {
                if let instr = s.nextInstruction, let d = s.distanceToManeuverMeters {
                    HStack(spacing: 2) {
                        Image(systemName: maneuverSymbol(instr)).font(.caption2.bold())
                        Text(RideActivityFormat.shortDistance(d, metric: s.useMetric))
                            .font(.caption.bold().monospacedDigit())
                    }
                    .foregroundStyle(.green)
                } else {
                    Text(s.powerWatts.map { "\($0)W" } ?? RideActivityFormat.duration(s.elapsedSeconds))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.red)
                }
            } minimal: {
                Image(systemName: "bicycle").foregroundStyle(.green)
            }
        }
    }

    private func stat(_ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct LockScreenRideView: View {
    let context: ActivityViewContext<RideActivityAttributes>

    var body: some View {
        let s = context.state
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                tile(RideActivityFormat.speed(s.speedMps, metric: s.useMetric),
                     RideActivityFormat.speedUnit(metric: s.useMetric), "Speed", .blue)
                tile(s.powerWatts.map { "\($0)" } ?? "--", "W", "Power", .red)
                tile(s.heartRateBpm.map { "\($0)" } ?? "--", "bpm", "HR", .pink)
                tile(RideActivityFormat.distance(s.distanceMeters, metric: s.useMetric),
                     RideActivityFormat.distanceUnit(metric: s.useMetric), "Dist", .green)
                tile(RideActivityFormat.duration(s.elapsedSeconds),
                     s.rideState == "recording" ? "" : (s.rideState == "auto" ? "auto-paused" : "paused"),
                     "Time", .purple)
            }
            if let instr = s.nextInstruction {
                HStack(spacing: 10) {
                    Image(systemName: maneuverSymbol(instr))
                        .font(.title2.bold())
                    if let d = s.distanceToManeuverMeters {
                        Text(RideActivityFormat.shortDistance(d, metric: s.useMetric))
                            .font(.title3.bold().monospacedDigit())
                    }
                    Text(instr).font(.subheadline).lineLimit(2)
                    Spacer()
                    if let r = s.remainingMeters {
                        Text("\(RideActivityFormat.shortDistance(r, metric: s.useMetric)) left")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.green.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
        }
        .padding(12)
        .foregroundStyle(.white)
    }

    private func tile(_ value: String, _ unit: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit.isEmpty ? label : unit)
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

func maneuverSymbol(_ instruction: String) -> String {
    let s = instruction.lowercased()
    if s.contains("arrive") || s.contains("destination") { return "flag.checkered" }
    if s.contains("u-turn") { return "arrow.uturn.left" }
    if s.contains("slight left") || s.contains("bear left") { return "arrow.up.left" }
    if s.contains("slight right") || s.contains("bear right") { return "arrow.up.right" }
    if s.contains("left") { return "arrow.turn.up.left" }
    if s.contains("right") { return "arrow.turn.up.right" }
    return "arrow.up"
}
