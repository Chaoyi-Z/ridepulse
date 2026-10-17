import SwiftUI
import Charts

/// Area chart of elevation vs. distance for a route.
struct ElevationProfileView: View {
    let distances: [Double]    // metres along the route, same count as elevations
    let elevations: [Double]   // metres
    let unit: SpeedUnit
    /// Optional marker for "you are here" (metres along the route).
    var progressMeters: Double? = nil

    private var points: [(x: Double, y: Double)] {
        let n = min(distances.count, elevations.count)
        guard n > 1 else { return [] }
        let dx = unit == .mph ? 1 / 1609.344 : 1 / 1000.0
        let dy = unit == .mph ? 3.28084 : 1.0
        // Thin very dense tracks so the chart stays fast.
        let stride = max(1, n / 400)
        return Swift.stride(from: 0, to: n, by: stride).map { (distances[$0] * dx, elevations[$0] * dy) }
    }

    var body: some View {
        let pts = points
        let minY = (pts.map(\.y).min() ?? 0)
        let maxY = (pts.map(\.y).max() ?? 1)
        let pad = max((maxY - minY) * 0.15, unit == .mph ? 20 : 6)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Elevation").font(.headline)
                Spacer()
                Text(String(format: "%.0f–%.0f %@", minY, maxY, unit == .mph ? "ft" : "m"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Distance", p.x), yStart: .value("Base", minY - pad), yEnd: .value("Elevation", p.y))
                        .foregroundStyle(.linearGradient(colors: [.green.opacity(0.45), .green.opacity(0.05)],
                                                         startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Distance", p.x), y: .value("Elevation", p.y))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let progressMeters {
                    let x = progressMeters * (unit == .mph ? 1 / 1609.344 : 1 / 1000.0)
                    RuleMark(x: .value("Here", x)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartYScale(domain: (minY - pad)...(maxY + pad))
            .chartXAxisLabel(unit == .mph ? "miles" : "km")
            .chartYAxis { AxisMarks(position: .leading) }
        }
    }
}
