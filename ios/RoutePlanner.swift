import Foundation
import MapKit
import AVFoundation
import Combine

/// One maneuver along the active route. `endIndex` is the index in
/// `ActiveRoute.coordinates` where this step ends (and the next begins).
struct NavStep: Identifiable {
    let id = UUID()
    let instruction: String
    let distanceMeters: Double
    let endIndex: Int
}

/// A route the rider has chosen to follow — either a preset or directions to a
/// searched destination.
struct ActiveRoute {
    enum Kind {
        case preset(PresetRoute)
        case destination(MKMapItem)
        /// Imported GPX / saved ride: followed as a track, turns derived from geometry.
        case custom(UUID)
    }

    let kind: Kind
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let steps: [NavStep]
    let totalMeters: Double
    /// Cumulative distance along `coordinates` for each vertex.
    let cumulativeMeters: [Double]

    var destination: CLLocationCoordinate2D { coordinates.last! }

    var mapRect: MKMapRect {
        MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
    }
}

/// Live navigation state, recomputed on every GPS fix.
struct NavProgress {
    var remainingMeters: Double
    var distanceToManeuverMeters: Double
    var nextInstruction: String
    var offRouteMeters: Double
    /// Metres travelled along the route (for the elevation marker).
    var alongRouteMeters: Double = 0
    /// Average grade over the next ~400 m, if an elevation profile is loaded.
    var gradeAheadPercent: Double? = nil
    var isOffRoute: Bool { offRouteMeters > 60 }
    var hasArrived: Bool { remainingMeters < 30 }
}

/// Destination search, route calculation (presets + arbitrary destinations)
/// and turn-by-turn progress tracking with optional voice prompts.
///
/// MapKit has no cycling transport type for third-party apps on iOS 17, so
/// routes use `.walking`, which follows bike paths and multi-use trails and
/// avoids highways. `openInAppleMaps()` hands off to Apple Maps' cycling mode.
@MainActor
final class RoutePlanner: ObservableObject {
    @Published private(set) var activeRoute: ActiveRoute?
    @Published private(set) var progress: NavProgress?
    /// Elevation along the active route (fetched in the background after activation).
    @Published private(set) var elevationProfile: ElevationProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [MKMapItem] = []

    /// Voice prompts for upcoming maneuvers (persisted via Settings).
    var voiceGuidanceEnabled: Bool {
        UserDefaults.standard.object(forKey: "voiceGuidance") as? Bool ?? true
    }

    private var lastSpokenStepID: UUID?
    private var lastSpokenFar = false
    private var lastRerouteAt: Date = .distantPast
    /// Index of the route vertex the rider was last matched to. Matching only
    /// searches forward from here so loops (start == end) and overlapping
    /// out-and-back legs don't snap the rider to the wrong part of the route.
    private var lastMatchedIndex = 0
    private var presetCache: [String: ActiveRoute] = [:]
    private var searchTask: Task<Void, Never>?

    // MARK: - Search

    func search(near location: CLLocation?) {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            // Debounce typing.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            // Bias toward the rider; default to Greater Boston.
            let center = location?.coordinate
                ?? CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 40_000,
                longitudinalMeters: 40_000
            )
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                searchResults = response.mapItems
            } catch {
                if !Task.isCancelled { searchResults = [] }
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
    }

    // MARK: - Route loading

    /// Route from the rider's current location to a searched destination.
    func navigate(to item: MKMapItem, from location: CLLocation?) async {
        guard let location else {
            errorMessage = "Waiting for a GPS fix before routing. Try again in a moment."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            let route = try await Self.directions(from: source, to: item)
            let built = Self.build(
                segments: [route],
                kind: .destination(item),
                name: item.name ?? "Destination"
            )
            activate(built)
        } catch is CancellationError {
            // Caller's view went away; nothing to report.
        } catch {
            errorMessage = "Couldn't find a route there: \(error.localizedDescription)"
        }
    }

    /// Start navigating a preset (snapped to real paths, cached per preset).
    func load(preset: PresetRoute) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            activate(try await buildPreset(preset))
        } catch is CancellationError {
            // View went away mid-request; nothing to report.
        } catch {
            errorMessage = "Couldn't load \(preset.name): \(error.localizedDescription)"
        }
    }

    /// Elevation profile for arbitrary coordinates (route detail pages).
    func elevationProfile(for coords: [CLLocationCoordinate2D], key: String) async -> ElevationProfile? {
        await ElevationService.shared.profile(for: coords, cacheKey: key)
    }

    /// Preview a preset's snapped path without starting navigation (detail map).
    func previewCoordinates(for preset: PresetRoute) async -> [CLLocationCoordinate2D]? {
        do {
            return try await buildPreset(preset).coordinates
        } catch {
            return nil
        }
    }

    /// Chain directions between a preset's waypoints into one continuous route.
    private func buildPreset(_ preset: PresetRoute) async throws -> ActiveRoute {
        if let cached = presetCache[preset.id] { return cached }
        var segments: [MKRoute] = []
        for (a, b) in zip(preset.waypoints, preset.waypoints.dropFirst()) {
            let from = MKMapItem(placemark: MKPlacemark(coordinate: a))
            let to = MKMapItem(placemark: MKPlacemark(coordinate: b))
            segments.append(try await Self.directions(from: from, to: to))
        }
        let built = Self.build(segments: segments, kind: .preset(preset), name: preset.name)
        presetCache[preset.id] = built
        return built
    }

    /// Navigate a saved/imported route. No directions request: the track is
    /// followed as-is and maneuvers are derived from heading changes.
    func load(saved route: SavedRoute) {
        let coords = route.coordinates
        guard coords.count > 1 else {
            errorMessage = "That route has no points."
            return
        }
        activate(Self.buildFromTrack(coords, kind: .custom(route.id), name: route.name))
    }

    func stopNavigation() {
        activeRoute = nil
        progress = nil
        elevationProfile = nil
        lastMatchedIndex = 0
        lastSpokenStepID = nil
        VoiceEngine.shared.stop()
    }

    private func activate(_ route: ActiveRoute) {
        activeRoute = route
        progress = nil
        lastMatchedIndex = 0
        elevationProfile = nil
        let key = "\(route.name)-\(route.coordinates.count)-\(Int(route.totalMeters))"
        Task { [weak self] in
            let profile = await ElevationService.shared.profile(for: route.coordinates, cacheKey: key)
            await MainActor.run {
                guard let self, self.activeRoute?.name == route.name else { return }
                self.elevationProfile = profile
            }
        }
        lastSpokenStepID = nil
        lastSpokenFar = false
        speak("Starting navigation to \(route.name). \(route.steps.first?.instruction ?? "")")
        prefetchPrompts(for: route)
    }

    /// Everything we might say on this route, so Azure audio is cached up front.
    private func prefetchPrompts(for route: ActiveRoute) {
        guard voiceGuidanceEnabled else { return }
        var phrases: [String] = ["You have arrived.", "Arrive at \(route.name)"]
        for step in route.steps {
            phrases.append("In \(Self.farPhrase), \(step.instruction)")
            phrases.append(step.instruction)
        }
        VoiceEngine.shared.prefetch(phrases)
    }

    /// Fixed lead-in distance for the early warning (200 m ≈ 650 ft), kept
    /// constant so the sentence can be synthesized and cached ahead of time.
    static var farPhrase: String {
        let metric = SpeedUnit.fromStored(UserDefaults.standard.string(forKey: "speedUnit") ?? SpeedUnit.mph.rawValue) == .kmh
        return metric ? "200 meters" : "600 feet"
    }

    // MARK: - Progress tracking

    /// Call on every location update.
    func update(with location: CLLocation) {
        guard let route = activeRoute, route.coordinates.count > 1 else { return }

        // Nearest vertex, searched in a window just behind → well ahead of the
        // last match (routes are dense enough that vertex snapping is fine).
        func nearest(in range: ClosedRange<Int>) -> (Int, Double) {
            var bestIndex = range.lowerBound
            var bestDistance = Double.greatestFiniteMagnitude
            for i in range {
                let c = route.coordinates[i]
                let d = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                if d < bestDistance { bestDistance = d; bestIndex = i }
            }
            return (bestIndex, bestDistance)
        }
        // Window by distance along the route (not vertex count) so loops and
        // out-and-back legs that share pavement can't match the wrong leg.
        let last = route.coordinates.count - 1
        let here = route.cumulativeMeters[lastMatchedIndex]
        var lo = lastMatchedIndex
        while lo > 0, route.cumulativeMeters[lo - 1] >= here - 120 { lo -= 1 }
        var hi = lastMatchedIndex
        while hi < last, route.cumulativeMeters[hi + 1] <= here + 600 { hi += 1 }
        var (bestIndex, bestDistance) = nearest(in: lo...hi)
        if bestDistance > 120 {
            // Well off the windowed match (rider skipped ahead / rejoined elsewhere): search everything.
            (bestIndex, bestDistance) = nearest(in: 0...last)
        }
        lastMatchedIndex = bestIndex

        let remaining = route.totalMeters - route.cumulativeMeters[bestIndex]
        let currentStep = route.steps.first { $0.endIndex > bestIndex } ?? route.steps.last
        let nextStepIndex = route.steps.firstIndex { $0.id == currentStep?.id }.map { $0 + 1 }
        let nextStep = nextStepIndex.flatMap { $0 < route.steps.count ? route.steps[$0] : nil }

        let toManeuver: Double
        let instruction: String
        if let currentStep {
            toManeuver = max(0, route.cumulativeMeters[min(currentStep.endIndex, route.coordinates.count - 1)]
                             - route.cumulativeMeters[bestIndex])
            instruction = nextStep?.instruction ?? "Arrive at \(route.name)"
        } else {
            toManeuver = remaining
            instruction = "Arrive at \(route.name)"
        }

        let along = route.cumulativeMeters[bestIndex]
        progress = NavProgress(
            remainingMeters: remaining,
            distanceToManeuverMeters: toManeuver,
            nextInstruction: instruction,
            offRouteMeters: bestDistance,
            alongRouteMeters: along,
            gradeAheadPercent: elevationProfile?.gradeAhead(from: along)
        )

        announceIfNeeded(step: nextStep, distance: toManeuver, arrived: remaining < 30)

        // Re-route destinations when well off course; presets just flag it.
        if bestDistance > 60, case .destination(let item) = route.kind,
           Date().timeIntervalSince(lastRerouteAt) > 20 {
            lastRerouteAt = Date()
            Task { await navigate(to: item, from: location) }
        }
    }

    private func announceIfNeeded(step: NavStep?, distance: Double, arrived: Bool) {
        guard voiceGuidanceEnabled else { return }
        if arrived {
            if lastSpokenStepID != nil { speak("You have arrived."); lastSpokenStepID = nil }
            return
        }
        guard let step else { return }
        if step.id != lastSpokenStepID {
            lastSpokenStepID = step.id
            lastSpokenFar = false
        }
        if distance < 200, distance > 60, !lastSpokenFar {
            lastSpokenFar = true
            speak("In \(Self.farPhrase), \(step.instruction)")
        } else if distance <= 60, lastSpokenFar {
            lastSpokenFar = false
            lastSpokenStepID = step.id
            speak(step.instruction)
        }
    }

    private func speak(_ text: String) {
        guard voiceGuidanceEnabled, !text.isEmpty else { return }
        VoiceEngine.shared.speak(text)
    }

    /// Speak a sample so the rider can audition a voice from Settings.
    func previewVoice() {
        VoiceEngine.shared.stop()
        VoiceEngine.shared.speak("In \(Self.farPhrase), turn left onto Memorial Drive.")
    }

    // MARK: - Apple Maps hand-off (true cycling directions)

    func appleMapsCyclingURL() -> URL? {
        guard let route = activeRoute else { return nil }
        let d = route.destination
        var comps = URLComponents(string: "https://maps.apple.com/")!
        comps.queryItems = [
            URLQueryItem(name: "daddr", value: "\(d.latitude),\(d.longitude)"),
            URLQueryItem(name: "dirflg", value: "b")
        ]
        return comps.url
    }

    // MARK: - Helpers

    private static func directions(from: MKMapItem, to: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = from
        request.destination = to
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "RidePulse", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No route returned"])
        }
        return route
    }

    private static func build(segments: [MKRoute], kind: ActiveRoute.Kind, name: String) -> ActiveRoute {
        var coords: [CLLocationCoordinate2D] = []
        var steps: [NavStep] = []
        for route in segments {
            for step in route.steps {
                let pts = step.polyline.coordinatesArray
                guard !pts.isEmpty else { continue }
                // Skip the empty "Proceed to …" step MapKit emits at the start of each segment
                // after the first, so chained presets read as one continuous route.
                if step.distance == 0 && !steps.isEmpty { continue }
                coords.append(contentsOf: pts)
                steps.append(NavStep(
                    instruction: cyclingWording(step.instructions),
                    distanceMeters: step.distance,
                    endIndex: coords.count - 1
                ))
            }
        }
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(coords.count)
        for i in 1..<max(coords.count, 1) {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            cumulative.append(cumulative[i - 1] + b.distance(from: a))
        }
        return ActiveRoute(
            kind: kind,
            name: name,
            coordinates: coords,
            steps: steps,
            totalMeters: cumulative.last ?? 0,
            cumulativeMeters: cumulative
        )
    }

    /// MapKit's walking directions say "Walk …"; reword for riders.
    private static func cyclingWording(_ text: String) -> String {
        if text.isEmpty { return "Continue" }
        var s = text
        for (from, to) in [("Walk over", "Ride over"), ("Walk along", "Ride along"),
                           ("Walk to", "Ride to"), ("Walk ", "Ride "), ("walk ", "ride ")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }

    /// Build a navigable route from raw coordinates: simplify, then emit a step
    /// wherever the heading changes enough to count as a turn.
    static func buildFromTrack(_ raw: [CLLocationCoordinate2D], kind: ActiveRoute.Kind, name: String) -> ActiveRoute {
        // Keep the full-resolution track for drawing/matching; decide turns on a simplified copy.
        let coords = raw
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(coords.count)
        for i in 1..<coords.count {
            cumulative.append(cumulative[i - 1] + distance(coords[i - 1], coords[i]))
        }
        let keyIndices = simplify(coords, tolerance: 12)   // Douglas–Peucker, indices into coords

        var steps: [NavStep] = []
        var lastStepIndex = 0
        func addStep(_ text: String, endIndex: Int) {
            steps.append(NavStep(instruction: text, distanceMeters: cumulative[endIndex] - cumulative[lastStepIndex], endIndex: endIndex))
            lastStepIndex = endIndex
        }
        steps.append(NavStep(instruction: "Follow the route", distanceMeters: 0, endIndex: 0))
        if keyIndices.count > 2 {
            for k in 1..<(keyIndices.count - 1) {
                let a = coords[keyIndices[k - 1]], b = coords[keyIndices[k]], c = coords[keyIndices[k + 1]]
                // Ignore micro-segments; GPS wiggle makes them look like turns.
                guard distance(a, b) > 15, distance(b, c) > 15 else { continue }
                var delta = bearing(b, c) - bearing(a, b)
                while delta > 180 { delta -= 360 }
                while delta < -180 { delta += 360 }
                let mag = abs(delta)
                guard mag >= 35 else { continue }
                let dir = delta > 0 ? "right" : "left"
                let text: String
                switch mag {
                case ..<60: text = "Slight \(dir)"
                case ..<120: text = "Turn \(dir)"
                case ..<160: text = "Sharp \(dir)"
                default: text = "Make a U-turn"
                }
                addStep(text, endIndex: keyIndices[k])
            }
        }
        addStep("Arrive at \(name)", endIndex: coords.count - 1)
        // Steps' endIndex marks where each step ends; the first placeholder step ends at the first turn.
        var fixed: [NavStep] = []
        for (i, st) in steps.enumerated() {
            let end = i + 1 < steps.count ? steps[i + 1].endIndex : coords.count - 1
            fixed.append(NavStep(instruction: st.instruction, distanceMeters: st.distanceMeters, endIndex: end))
        }
        fixed.removeLast()   // the trailing "Arrive" marker is represented by the final step's end
        return ActiveRoute(kind: kind, name: name, coordinates: coords, steps: fixed,
                           totalMeters: cumulative.last ?? 0, cumulativeMeters: cumulative)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Initial bearing a→b in degrees (0 = north, clockwise).
    private static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Douglas–Peucker simplification returning the indices to keep.
    private static func simplify(_ pts: [CLLocationCoordinate2D], tolerance: Double) -> [Int] {
        guard pts.count > 2 else { return Array(pts.indices) }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let (lo, hi) = stack.popLast() {
            var maxD = 0.0, idx = -1
            for i in (lo + 1)..<hi {
                let d = perpendicular(pts[i], pts[lo], pts[hi])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > tolerance, idx > 0 {
                keep[idx] = true
                stack.append((lo, idx)); stack.append((idx, hi))
            }
        }
        return keep.indices.filter { keep[$0] }
    }

    /// Approximate perpendicular distance (metres) from p to segment a–b using a local flat projection.
    private static func perpendicular(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let kx = 111_320.0 * cos(a.latitude * .pi / 180), ky = 110_540.0
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * kx, by = (b.latitude - a.latitude) * ky
        let px = (p.longitude - a.longitude) * kx, py = (p.latitude - a.latitude) * ky
        let len2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
        if len2 == 0 { return hypot(px - ax, py - ay) }
        let t = max(0, min(1, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2))
        return hypot(px - (ax + t * (bx - ax)), py - (ay + t * (by - ay)))
    }

    static func spokenDistance(_ meters: Double) -> String {
        let useMetric = SpeedUnit.fromStored(
            UserDefaults.standard.string(forKey: "speedUnit") ?? SpeedUnit.mph.rawValue
        ) == .kmh
        if useMetric {
            return meters >= 950 ? String(format: "%.1f kilometers", meters / 1000)
                                 : "\(Int((meters / 50).rounded() * 50)) meters"
        }
        let feet = meters * 3.28084
        if feet >= 900 { return String(format: "%.1f miles", feet / 5280) }
        return "\(Int((feet / 50).rounded() * 50)) feet"
    }

    /// Short display string, e.g. "250 ft", "1.2 mi", "400 m".
    static func shortDistance(_ meters: Double, unit: SpeedUnit) -> String {
        if unit == .kmh {
            return meters >= 950 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
        }
        let feet = meters * 3.28084
        return feet >= 900 ? String(format: "%.1f mi", feet / 5280) : "\(Int((feet / 10).rounded() * 10)) ft"
    }
}

extension MKPolyline {
    var coordinatesArray: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
