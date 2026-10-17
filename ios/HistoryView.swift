import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue

    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "No rides yet",
                        systemImage: "bicycle",
                        description: Text("Finish your first ride and it will show up here.")
                    )
                } else {
                    List {
                        ForEach(rides) { ride in
                            NavigationLink {
                                RideDetailView(ride: ride)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(RideStore.formatDate(ride.startDate))
                                        .font(.headline)
                                    HStack(spacing: 12) {
                                        Label(
                                            "\(unit.distanceString(meters: ride.distanceMeters)) \(unit.distanceLabel)",
                                            systemImage: "map"
                                        )
                                        Label(
                                            RideStore.formatDuration(ride.durationSeconds),
                                            systemImage: "timer"
                                        )
                                        if ride.avgPowerWatts > 0 {
                                            Label(
                                                "\(Int(ride.avgPowerWatts)) W",
                                                systemImage: "bolt"
                                            )
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteRides)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func deleteRides(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rides[index])
        }
        try? modelContext.save()
    }
}
