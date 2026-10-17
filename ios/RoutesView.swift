import SwiftUI
import MapKit
import SwiftData
import UniformTypeIdentifiers

/// Routes tab: search a destination or pick a preset Boston-area ride.
struct RoutesView: View {
    @EnvironmentObject private var planner: RoutePlanner
    @EnvironmentObject private var locationManager: LocationSpeedManager
    @Binding var selectedTab: AppTab
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @State private var showImporter = false
    @State private var importError: String?

    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }

    var body: some View {
        NavigationStack {
            List {
                myRoutesSection

                if let route = planner.activeRoute {
                    Section("Navigating") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.name).font(.headline)
                                Text("\(unit.distanceString(meters: route.totalMeters)) \(unit.distanceLabel) · \(route.steps.count) turns")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Show") { selectedTab = .ride }
                                .buttonStyle(.borderedProminent)
                            Button(role: .destructive) {
                                planner.stopNavigation()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section {
                    if planner.isLoading {
                        HStack { ProgressView(); Text("Calculating route…").foregroundStyle(.secondary) }
                    }
                    if let err = planner.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    if planner.searchResults.isEmpty && !planner.searchQuery.isEmpty {
                        Text("No places found.").foregroundStyle(.secondary)
                    }
                    ForEach(planner.searchResults, id: \.self) { item in
                        Button {
                            Task {
                                await planner.navigate(to: item, from: locationManager.currentLocation)
                                if planner.activeRoute != nil {
                                    planner.clearSearch()
                                    selectedTab = .ride
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown").foregroundStyle(.primary)
                                    if let sub = Self.subtitle(for: item) {
                                        Text(sub).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let loc = locationManager.currentLocation {
                                    let d = CLLocation(latitude: item.placemark.coordinate.latitude,
                                                       longitude: item.placemark.coordinate.longitude)
                                        .distance(from: loc)
                                    Text(RoutePlanner.shortDistance(d, unit: unit))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Destination")
                } footer: {
                    Text("In-app routing follows bike paths and trails (MapKit walking network). For Apple's cycling-specific routing, use “Open in Apple Maps” from the Ride screen.")
                }

                ForEach(PresetRoute.Category.allCases, id: \.self) { category in
                    Section {
                        ForEach(sortedPresets(in: category)) { preset in
                            NavigationLink(value: preset) {
                                PresetRouteRow(
                                    preset: preset,
                                    startDistance: startDistance(to: preset),
                                    unit: unit
                                )
                            }
                        }
                    } header: {
                        Text(category.rawValue)
                    } footer: {
                        if category == .path && locationManager.currentLocation != nil {
                            Text("Sorted by distance from you to the start.")
                        }
                    }
                }
            }
            .navigationTitle("Routes")
            .navigationDestination(for: PresetRoute.self) { preset in
                PresetRouteDetailView(preset: preset, selectedTab: $selectedTab)
            }
            .navigationDestination(for: SavedRoute.self) { route in
                SavedRouteDetailView(route: route, selectedTab: $selectedTab)
            }
            .searchable(text: $planner.searchQuery, prompt: "Search address or place")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml, .data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { importGPX(from: url) }
            }
            .onOpenURL { url in
                if url.pathExtension.lowercased() == "gpx" { importGPX(from: url) }
            }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil },
                                                          set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .onChange(of: planner.searchQuery) { _, _ in
                planner.search(near: locationManager.currentLocation)
            }
        }
    }

    @ViewBuilder
    private var myRoutesSection: some View {
        Section {
            if savedRoutes.isEmpty {
                Button { showImporter = true } label: {
                    Label("Import a GPX file…", systemImage: "square.and.arrow.down")
                }
            }
            ForEach(savedRoutes) { route in
                NavigationLink(value: route) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(route.name).font(.headline)
                            Spacer()
                            Text("\(unit.distanceString(meters: route.distanceMeters)) \(unit.distanceLabel)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Label(route.source == "ride" ? "From a ride" : "GPX",
                                  systemImage: route.source == "ride" ? "bicycle" : "doc")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let start = route.start, let loc = locationManager.currentLocation {
                                let d = CLLocation(latitude: start.latitude, longitude: start.longitude).distance(from: loc)
                                Label(RoutePlanner.shortDistance(d, unit: unit) + " to start", systemImage: "location")
                                    .font(.caption2).foregroundStyle(d < 3200 ? .green : .secondary)
                            }
                            Spacer()
                            if route.isLoop {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete { idx in
                for i in idx { modelContext.delete(savedRoutes[i]) }
                try? modelContext.save()
            }
        } header: {
            Text("My Routes")
        } footer: {
            Text("Import GPX files from Strava, Komoot or RideWithGPS (share the file to RidePulse, or use the import button), or save any ride from History as a route.")
        }
    }

    private func importGPX(from url: URL) {
        do {
            let r = try GPXImporter.parse(url: url)
            let name = r.name ?? url.deletingPathExtension().lastPathComponent
            let route = SavedRoute(name: name, source: "gpx", coordinates: r.coordinates, elevations: r.elevations)
            modelContext.insert(route)
            try? modelContext.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func startDistance(to preset: PresetRoute) -> Double? {
        guard let loc = locationManager.currentLocation else { return nil }
        return CLLocation(latitude: preset.start.latitude, longitude: preset.start.longitude)
            .distance(from: loc)
    }

    /// Nearest start first when we know where the rider is; file order otherwise.
    private func sortedPresets(in category: PresetRoute.Category) -> [PresetRoute] {
        let presets = PresetRoute.all.filter { $0.category == category }
        guard locationManager.currentLocation != nil else { return presets }
        return presets.sorted { (startDistance(to: $0) ?? 0) < (startDistance(to: $1) ?? 0) }
    }

    static func subtitle(for item: MKMapItem) -> String? {
        let p = item.placemark
        let parts = [p.thoroughfare.map { ($0, p.subThoroughfare) }.map { "\($0.1 ?? "") \($0.0)".trimmingCharacters(in: .whitespaces) },
                     p.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct PresetRouteRow: View {
    let preset: PresetRoute
    var startDistance: Double? = nil
    var unit: SpeedUnit = .mph

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(preset.name).font(.headline)
                Spacer()
                Text(String(format: "~%.0f mi", preset.approxMiles))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(preset.area).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let d = startDistance {
                    Label(RoutePlanner.shortDistance(d, unit: unit) + " to start",
                          systemImage: "location")
                        .font(.caption2)
                        .foregroundStyle(d < 3200 ? .green : .secondary)
                }
                Spacer()
                Text(preset.difficulty.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(difficultyColor.opacity(0.15))
                    .foregroundStyle(difficultyColor)
                    .clipShape(Capsule())
                if preset.isLoop {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var difficultyColor: Color {
        switch preset.difficulty {
        case .easy: return .green
        case .moderate: return .orange
        case .hard: return .red
        }
    }
}

struct PresetRouteDetailView: View {
    let preset: PresetRoute
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var planner: RoutePlanner
    @EnvironmentObject private var locationManager: LocationSpeedManager
    @Environment(\.openURL) private var openURL
    @State private var path: [CLLocationCoordinate2D]?
    @State private var camera: MapCameraPosition = .automatic
    @State private var profile: ElevationProfile?
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $camera) {
                    if let path, path.count > 1 {
                        MapPolyline(coordinates: path).stroke(.green, lineWidth: 5)
                    } else {
                        MapPolyline(coordinates: preset.waypoints)
                            .stroke(.green.opacity(0.5), style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
                    }
                    Marker("Start", systemImage: "flag.fill", coordinate: preset.start).tint(.green)
                    if !preset.isLoop {
                        Marker("Finish", systemImage: "flag.checkered", coordinate: preset.end).tint(.red)
                    }
                    UserAnnotation()
                }
                // Map content doesn't always refresh when `path` arrives; rebuild it.
                .id(path?.count ?? 0)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    if path == nil {
                        ProgressView().padding(8)
                            .background(.ultraThinMaterial, in: Capsule()).padding(8)
                    }
                }

                HStack(spacing: 16) {
                    stat(String(format: "~%.0f", preset.approxMiles), "miles")
                    if let profile {
                        stat(String(format: "%.0f", profile.totalGain * (unit == .mph ? 3.28084 : 1)),
                             unit == .mph ? "ft climb" : "m climb")
                    } else {
                        stat(preset.difficulty.rawValue, "difficulty")
                    }
                    stat(preset.isLoop ? "Loop" : "Point-to-point", "type")
                }

                if let profile {
                    ElevationProfileView(distances: profile.distances, elevations: profile.elevations, unit: unit)
                        .frame(height: 150)
                }

                Text(preset.area).font(.subheadline).foregroundStyle(.secondary)
                Text(preset.summary).font(.body)

                Button {
                    Task {
                        await planner.load(preset: preset)
                        if planner.activeRoute != nil { selectedTab = .ride }
                    }
                } label: {
                    Label("Navigate this route", systemImage: "location.north.line.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.green).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(planner.isLoading)

                Button {
                    let s = preset.start
                    var comps = URLComponents(string: "https://maps.apple.com/")!
                    comps.queryItems = [URLQueryItem(name: "daddr", value: "\(s.latitude),\(s.longitude)"),
                                        URLQueryItem(name: "dirflg", value: "b")]
                    if let url = comps.url { openURL(url) }
                } label: {
                    Label("Bike to the start in Apple Maps", systemImage: "map")
                        .font(.subheadline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let err = planner.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            path = await planner.previewCoordinates(for: preset)
            if let path, path.count > 1 {
                camera = .rect(MKPolyline(coordinates: path, count: path.count).boundingMapRect
                    .insetBy(dx: -2000, dy: -2000))
                profile = await planner.elevationProfile(for: path, key: "\(preset.name)-\(path.count)")
            } else {
                camera = .rect(MKPolyline(coordinates: preset.waypoints, count: preset.waypoints.count)
                    .boundingMapRect.insetBy(dx: -2000, dy: -2000))
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


/// Detail page for an imported / saved route.
struct SavedRouteDetailView: View {
    @Bindable var route: SavedRoute
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var planner: RoutePlanner
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    @State private var camera: MapCameraPosition = .automatic
    @State private var isRenaming = false
    @State private var newName = ""

    private var unit: SpeedUnit { SpeedUnit.fromStored(speedUnitRaw) }

    var body: some View {
        let coords = route.coordinates
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $camera) {
                    if coords.count > 1 {
                        MapPolyline(coordinates: coords).stroke(.green, lineWidth: 5)
                    }
                    if let s = coords.first {
                        Marker("Start", systemImage: "flag.fill", coordinate: s).tint(.green)
                    }
                    if !route.isLoop, let e = coords.last {
                        Marker("Finish", systemImage: "flag.checkered", coordinate: e).tint(.red)
                    }
                    UserAnnotation()
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 16) {
                    stat("\(unit.distanceString(meters: route.distanceMeters))", unit.distanceLabel)
                    stat(String(format: "%.0f", route.elevationGainMeters * (unit == .mph ? 3.28084 : 1)),
                         unit == .mph ? "ft climb" : "m climb")
                    stat(route.isLoop ? "Loop" : "A → B", "type")
                }

                if !route.elevations.isEmpty {
                    ElevationProfileView(distances: cumulativeDistances(coords), elevations: route.elevations, unit: unit)
                        .frame(height: 140)
                }

                Button {
                    planner.load(saved: route)
                    if planner.activeRoute != nil { selectedTab = .ride }
                } label: {
                    Label("Navigate this route", systemImage: "location.north.line.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.green).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Text(route.source == "ride" ? "Saved from a recorded ride" : "Imported from GPX")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newName = route.name; isRenaming = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        modelContext.delete(route); try? modelContext.save(); dismiss()
                    } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Rename route", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { route.name = newName.trimmingCharacters(in: .whitespaces); try? modelContext.save() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if coords.count > 1 {
                camera = .rect(MKPolyline(coordinates: coords, count: coords.count).boundingMapRect.insetBy(dx: -1500, dy: -1500))
            }
        }
    }

    private func cumulativeDistances(_ coords: [CLLocationCoordinate2D]) -> [Double] {
        var out = [0.0]
        for i in 1..<max(coords.count, 1) {
            out.append(out[i - 1] + CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                .distance(from: CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)))
        }
        return out
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
