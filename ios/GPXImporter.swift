import Foundation
import CoreLocation

/// Minimal GPX reader: collects track points (trkpt), falling back to route
/// points (rtept) and then waypoints (wpt). Reads the first <name> for a title.
final class GPXImporter: NSObject, XMLParserDelegate {
    struct Result {
        var name: String?
        var coordinates: [CLLocationCoordinate2D]
        var elevations: [Double]
    }

    enum ImportError: LocalizedError {
        case unreadable, noPoints
        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file isn't valid GPX."
            case .noPoints: return "No track, route or waypoints were found in the file."
            }
        }
    }

    private var trk: [(CLLocationCoordinate2D, Double?)] = []
    private var rte: [(CLLocationCoordinate2D, Double?)] = []
    private var wpt: [(CLLocationCoordinate2D, Double?)] = []
    private var current: (CLLocationCoordinate2D, Double?)?
    private var currentKind = ""
    private var text = ""
    private var name: String?
    private var depthInMetadata = 0

    static func parse(url: URL) throws -> Result {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> Result {
        let importer = GPXImporter()
        let parser = XMLParser(data: data)
        parser.delegate = importer
        guard parser.parse() else { throw ImportError.unreadable }
        let pts = !importer.trk.isEmpty ? importer.trk : (!importer.rte.isEmpty ? importer.rte : importer.wpt)
        guard pts.count >= 2 else { throw ImportError.noPoints }
        let coords = pts.map { $0.0 }
        let eles = pts.compactMap { $0.1 }
        return Result(name: importer.name, coordinates: coords,
                      elevations: eles.count == pts.count ? eles : [])
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        text = ""
        switch element {
        case "trkpt", "rtept", "wpt":
            if let lat = Double(attributes["lat"] ?? ""), let lon = Double(attributes["lon"] ?? "") {
                current = (CLLocationCoordinate2D(latitude: lat, longitude: lon), nil)
                currentKind = element
            }
        case "metadata": depthInMetadata += 1
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "ele":
            if current != nil, let e = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) { current?.1 = e }
        case "name":
            // Prefer the track/route name; metadata or waypoint names are fallbacks.
            let n = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty, current == nil, (name == nil || depthInMetadata == 0) { name = n }
        case "trkpt": if let c = current { trk.append(c) }; current = nil
        case "rtept": if let c = current { rte.append(c) }; current = nil
        case "wpt": if let c = current { wpt.append(c) }; current = nil
        case "metadata": depthInMetadata -= 1
        default: break
        }
    }
}
