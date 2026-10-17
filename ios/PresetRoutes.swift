import Foundation
import CoreLocation

/// A curated, popular Boston-area cycling route. Waypoints are coarse anchor
/// points; RoutePlanner snaps the path between them to real bike paths/roads
/// via MapKit directions when the route is loaded.
struct PresetRoute: Identifiable, Hashable {
    let id: String
    let name: String
    let area: String
    let approxMiles: Double
    let difficulty: Difficulty
    let category: Category
    let summary: String
    let waypoints: [CLLocationCoordinate2D]

    /// How the routes are grouped in the Routes tab.
    enum Category: String, CaseIterable {
        case path = "Paths & Greenways"
        case road = "Road Rides (20–30 mi)"
    }

    enum Difficulty: String {
        case easy = "Easy"
        case moderate = "Moderate"
        case hard = "Hard"
    }

    static func == (lhs: PresetRoute, rhs: PresetRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var start: CLLocationCoordinate2D { waypoints.first! }
    var end: CLLocationCoordinate2D { waypoints.last! }
    var isLoop: Bool {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) < 400
    }
}

extension PresetRoute {
    static let all: [PresetRoute] = [
        PresetRoute(
            id: "charles-river-loop",
            name: "Charles River Loop",
            area: "Boston · Cambridge · Watertown",
            approxMiles: 17,
            difficulty: .moderate,
            category: .path,
            summary: "The classic Dr. Paul Dudley White path: Museum of Science out to Watertown Square on the Cambridge side, back along the Esplanade. Flat, car-free, great skyline views.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3677, longitude: -71.0712), // Museum of Science
                CLLocationCoordinate2D(latitude: 42.3625, longitude: -71.0772), // Longfellow (Cambridge)
                CLLocationCoordinate2D(latitude: 42.3580, longitude: -71.0930), // Harvard Bridge (Cambridge)
                CLLocationCoordinate2D(latitude: 42.3535, longitude: -71.1105), // BU Bridge (Cambridge)
                CLLocationCoordinate2D(latitude: 42.3690, longitude: -71.1225), // Anderson Bridge / Harvard
                CLLocationCoordinate2D(latitude: 42.3645, longitude: -71.1570), // Arsenal St Bridge
                CLLocationCoordinate2D(latitude: 42.3655, longitude: -71.1855), // Watertown Square
                CLLocationCoordinate2D(latitude: 42.3615, longitude: -71.1560), // Arsenal St (Boston side)
                CLLocationCoordinate2D(latitude: 42.3665, longitude: -71.1300), // Eliot Bridge (Boston side)
                CLLocationCoordinate2D(latitude: 42.3515, longitude: -71.1098), // BU Bridge (Boston)
                CLLocationCoordinate2D(latitude: 42.3545, longitude: -71.0905), // Harvard Bridge (Boston)
                CLLocationCoordinate2D(latitude: 42.3560, longitude: -71.0735), // Esplanade / Hatch Shell
                CLLocationCoordinate2D(latitude: 42.3677, longitude: -71.0712)  // back to Museum of Science
            ]
        ),
        PresetRoute(
            id: "esplanade-short-loop",
            name: "Esplanade Short Loop",
            area: "Back Bay · MIT",
            approxMiles: 5,
            difficulty: .easy,
            category: .path,
            summary: "Quick spin: Hatch Shell to the BU Bridge, cross to Cambridge, back over the Harvard (Mass Ave) Bridge. Good after-work ride.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3560, longitude: -71.0735), // Hatch Shell
                CLLocationCoordinate2D(latitude: 42.3545, longitude: -71.0905), // Harvard Bridge (Boston)
                CLLocationCoordinate2D(latitude: 42.3515, longitude: -71.1098), // BU Bridge (Boston)
                CLLocationCoordinate2D(latitude: 42.3535, longitude: -71.1105), // BU Bridge (Cambridge)
                CLLocationCoordinate2D(latitude: 42.3580, longitude: -71.0930), // Harvard Bridge (Cambridge)
                CLLocationCoordinate2D(latitude: 42.3560, longitude: -71.0735)  // Hatch Shell
            ]
        ),
        PresetRoute(
            id: "minuteman-bikeway",
            name: "Minuteman Bikeway",
            area: "Cambridge · Arlington · Lexington · Bedford",
            approxMiles: 10,
            difficulty: .easy,
            category: .path,
            summary: "Rail-trail from Alewife to Bedford Depot through Arlington and Lexington centers. Paved, gentle grade, plenty of coffee stops. Ride back for ~20 mi.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3955, longitude: -71.1420), // Alewife
                CLLocationCoordinate2D(latitude: 42.4155, longitude: -71.1565), // Arlington Center
                CLLocationCoordinate2D(latitude: 42.4325, longitude: -71.1900), // Arlington Heights
                CLLocationCoordinate2D(latitude: 42.4480, longitude: -71.2300), // Lexington Depot
                CLLocationCoordinate2D(latitude: 42.4870, longitude: -71.2770)  // Bedford Depot
            ]
        ),
        PresetRoute(
            id: "emerald-necklace",
            name: "Emerald Necklace",
            area: "Boston Common → Franklin Park",
            approxMiles: 7,
            difficulty: .easy,
            category: .path,
            summary: "Olmsted's park chain: Common, Public Garden, Comm Ave Mall, the Fens, Riverway, Jamaica Pond, Arnold Arboretum, ending at Franklin Park. Mostly path with a few road crossings.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3560, longitude: -71.0625), // Boston Common
                CLLocationCoordinate2D(latitude: 42.3541, longitude: -71.0700), // Public Garden
                CLLocationCoordinate2D(latitude: 42.3500, longitude: -71.0880), // Comm Ave @ Mass Ave
                CLLocationCoordinate2D(latitude: 42.3435, longitude: -71.0950), // Back Bay Fens
                CLLocationCoordinate2D(latitude: 42.3375, longitude: -71.1090), // Riverway
                CLLocationCoordinate2D(latitude: 42.3200, longitude: -71.1215), // Jamaica Pond
                CLLocationCoordinate2D(latitude: 42.3105, longitude: -71.1200), // Arnold Arboretum
                CLLocationCoordinate2D(latitude: 42.3030, longitude: -71.0975)  // Franklin Park
            ]
        ),
        PresetRoute(
            id: "southwest-corridor",
            name: "Southwest Corridor Park",
            area: "Back Bay → Forest Hills",
            approxMiles: 5,
            difficulty: .easy,
            category: .path,
            summary: "Linear park bike path along the Orange Line from Back Bay Station to Forest Hills. Fully separated from traffic; a favorite commuter route.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3474, longitude: -71.0754), // Back Bay Station
                CLLocationCoordinate2D(latitude: 42.3415, longitude: -71.0835), // Mass Ave
                CLLocationCoordinate2D(latitude: 42.3365, longitude: -71.0892), // Ruggles
                CLLocationCoordinate2D(latitude: 42.3230, longitude: -71.0995), // Jackson Square
                CLLocationCoordinate2D(latitude: 42.3105, longitude: -71.1075), // Green St
                CLLocationCoordinate2D(latitude: 42.3005, longitude: -71.1140)  // Forest Hills
            ]
        ),
        PresetRoute(
            id: "castle-island-harborwalk",
            name: "Castle Island & Harborwalk",
            area: "Seaport · South Boston",
            approxMiles: 8,
            difficulty: .easy,
            category: .path,
            summary: "Fan Pier along the Harborwalk to Castle Island, around Pleasure Bay (the Sugar Bowl), then Carson Beach to JFK/UMass. Flat with ocean breeze.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3540, longitude: -71.0455), // Fan Pier
                CLLocationCoordinate2D(latitude: 42.3440, longitude: -71.0330), // Summer St / Marine Park approach
                CLLocationCoordinate2D(latitude: 42.3375, longitude: -71.0105), // Castle Island
                CLLocationCoordinate2D(latitude: 42.3340, longitude: -71.0085), // Head Island (Sugar Bowl)
                CLLocationCoordinate2D(latitude: 42.3310, longitude: -71.0400), // Carson Beach
                CLLocationCoordinate2D(latitude: 42.3205, longitude: -71.0520)  // JFK/UMass
            ]
        ),
        PresetRoute(
            id: "neponset-greenway",
            name: "Neponset River Greenway",
            area: "Dorchester · Milton · Mattapan",
            approxMiles: 5,
            difficulty: .easy,
            category: .path,
            summary: "Riverside trail from Tenean Beach past Pope John Paul II Park to Lower Mills and Mattapan Square. Quiet and scenic, with marsh boardwalks.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.2965, longitude: -71.0480), // Tenean Beach
                CLLocationCoordinate2D(latitude: 42.2850, longitude: -71.0470), // Pope John Paul II Park
                CLLocationCoordinate2D(latitude: 42.2720, longitude: -71.0680), // Lower Mills
                CLLocationCoordinate2D(latitude: 42.2680, longitude: -71.0920)  // Mattapan Square
            ]
        ),

        // MARK: Road rides (20–30 mi) — Cambridge starts first

        PresetRoute(
            id: "weston-lincoln-loop",
            name: "Weston–Lincoln Loop",
            area: "Harvard Sq · Belmont · Weston · Lincoln · Waltham",
            approxMiles: 27,
            difficulty: .moderate,
            category: .road,
            summary: "The go-to road loop from Cambridge: out past Fresh Pond and Belmont Center, over Belmont Hill into Weston's quiet lanes, up to Lincoln Center, then back along Rt 117 through Waltham and Watertown to Harvard Square. Rolling, shaded, low traffic once past Belmont.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3736, longitude: -71.1190), // Harvard Square
                CLLocationCoordinate2D(latitude: 42.3845, longitude: -71.1480), // Fresh Pond
                CLLocationCoordinate2D(latitude: 42.3960, longitude: -71.1790), // Belmont Center
                CLLocationCoordinate2D(latitude: 42.3665, longitude: -71.3030), // Weston Center
                CLLocationCoordinate2D(latitude: 42.4260, longitude: -71.3040), // Lincoln Center
                CLLocationCoordinate2D(latitude: 42.3760, longitude: -71.2360), // Waltham (Moody St)
                CLLocationCoordinate2D(latitude: 42.3655, longitude: -71.1855), // Watertown Square
                CLLocationCoordinate2D(latitude: 42.3736, longitude: -71.1190)  // Harvard Square
            ]
        ),
        PresetRoute(
            id: "mystic-lakes-lexington-loop",
            name: "Mystic Lakes & Lexington Loop",
            area: "Harvard Sq · Medford · Winchester · Lexington · Arlington",
            approxMiles: 22,
            difficulty: .easy,
            category: .road,
            summary: "A mellow road loop north of Cambridge: Alewife to the Mystic Lakes, through Winchester Center, west on quiet roads to Lexington, then home down the Minuteman Bikeway through Arlington. Mostly flat with one gentle climb into Lexington.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3736, longitude: -71.1190), // Harvard Square
                CLLocationCoordinate2D(latitude: 42.3955, longitude: -71.1420), // Alewife
                CLLocationCoordinate2D(latitude: 42.4270, longitude: -71.1420), // Mystic Lakes
                CLLocationCoordinate2D(latitude: 42.4520, longitude: -71.1370), // Winchester Center
                CLLocationCoordinate2D(latitude: 42.4480, longitude: -71.2300), // Lexington Center
                CLLocationCoordinate2D(latitude: 42.4155, longitude: -71.1565), // Arlington Center
                CLLocationCoordinate2D(latitude: 42.3736, longitude: -71.1190)  // Harvard Square
            ]
        ),
        PresetRoute(
            id: "newton-hills-wellesley-loop",
            name: "Newton Hills & Wellesley Loop",
            area: "Harvard Sq · Watertown · Newton · Wellesley",
            approxMiles: 28,
            difficulty: .moderate,
            category: .road,
            summary: "Climbing practice close to home: Charles River path to Watertown, up Commonwealth Ave over the Newton Hills (including Heartbreak Hill, in reverse), out to Wellesley Square, back through Newton Upper Falls and Newton Centre, and home over the BU Bridge.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3736, longitude: -71.1190), // Harvard Square
                CLLocationCoordinate2D(latitude: 42.3655, longitude: -71.1855), // Watertown Square
                CLLocationCoordinate2D(latitude: 42.3375, longitude: -71.2090), // Newton City Hall (Comm Ave)
                CLLocationCoordinate2D(latitude: 42.2968, longitude: -71.2924), // Wellesley Square
                CLLocationCoordinate2D(latitude: 42.3105, longitude: -71.2210), // Newton Upper Falls
                CLLocationCoordinate2D(latitude: 42.3295, longitude: -71.1925), // Newton Centre
                CLLocationCoordinate2D(latitude: 42.3515, longitude: -71.1098), // BU Bridge
                CLLocationCoordinate2D(latitude: 42.3736, longitude: -71.1190)  // Harvard Square
            ]
        ),

        PresetRoute(
            id: "dover-sherborn-loop",
            name: "Dover–Sherborn Loop",
            area: "Wellesley · Dover · Medfield · Sherborn · Natick",
            approxMiles: 26,
            difficulty: .moderate,
            category: .road,
            summary: "The quintessential Boston-area road ride: quiet, rolling country roads through Dover's horse farms, Medfield and Sherborn, returning via Natick. Starts at Wellesley Square — about 12 mi from Cambridge via the Charles River path (or the Worcester Line from Lansdowne). Rolling hills, light traffic, few lights.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.2968, longitude: -71.2924), // Wellesley Square
                CLLocationCoordinate2D(latitude: 42.2457, longitude: -71.2822), // Dover Center
                CLLocationCoordinate2D(latitude: 42.1875, longitude: -71.3065), // Medfield Center
                CLLocationCoordinate2D(latitude: 42.2392, longitude: -71.3690), // Sherborn Center
                CLLocationCoordinate2D(latitude: 42.2834, longitude: -71.3468), // Natick Center
                CLLocationCoordinate2D(latitude: 42.2968, longitude: -71.2924)  // Wellesley Square
            ]
        ),
        PresetRoute(
            id: "concord-battle-road-loop",
            name: "Concord & Battle Road Loop",
            area: "Cambridge · Lexington · Concord · Bedford",
            approxMiles: 30,
            difficulty: .moderate,
            category: .road,
            summary: "Minuteman Bikeway out to Lexington, then Battle Road (Rt 2A) through Minute Man National Park to Concord Center and the Old North Bridge. Return on Rt 62 to Bedford Depot and ride the bikeway home. Mix of car-free path and classic New England roads.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3955, longitude: -71.1420), // Alewife
                CLLocationCoordinate2D(latitude: 42.4155, longitude: -71.1565), // Arlington Center
                CLLocationCoordinate2D(latitude: 42.4480, longitude: -71.2300), // Lexington Depot
                CLLocationCoordinate2D(latitude: 42.4495, longitude: -71.2690), // Minute Man Visitor Center
                CLLocationCoordinate2D(latitude: 42.4604, longitude: -71.3489), // Concord Center
                CLLocationCoordinate2D(latitude: 42.4690, longitude: -71.3505), // Old North Bridge
                CLLocationCoordinate2D(latitude: 42.4870, longitude: -71.2770), // Bedford Depot
                CLLocationCoordinate2D(latitude: 42.4480, longitude: -71.2300), // Lexington Depot
                CLLocationCoordinate2D(latitude: 42.3955, longitude: -71.1420)  // Alewife
            ]
        ),
        PresetRoute(
            id: "blue-hills-loop",
            name: "Blue Hills & Quincy Shore",
            area: "Dorchester · Milton · Blue Hills · Quincy",
            approxMiles: 25,
            difficulty: .hard,
            category: .road,
            summary: "Boston's climbing ride. Out through Lower Mills to Houghton's Pond, up and over Chickatawbut Road through the Blue Hills Reservation (the steepest sustained climb near the city), then down to Quincy Center and home flat along Wollaston Beach and the Neponset.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3205, longitude: -71.0520), // JFK/UMass
                CLLocationCoordinate2D(latitude: 42.2720, longitude: -71.0680), // Lower Mills
                CLLocationCoordinate2D(latitude: 42.2115, longitude: -71.0940), // Houghton's Pond
                CLLocationCoordinate2D(latitude: 42.2110, longitude: -71.0730), // Chickatawbut Rd (summit area)
                CLLocationCoordinate2D(latitude: 42.2200, longitude: -71.0380), // Chickatawbut Rd / Rt 28
                CLLocationCoordinate2D(latitude: 42.2510, longitude: -71.0040), // Quincy Center
                CLLocationCoordinate2D(latitude: 42.2720, longitude: -71.0040), // Wollaston Beach
                CLLocationCoordinate2D(latitude: 42.2965, longitude: -71.0480), // Tenean Beach
                CLLocationCoordinate2D(latitude: 42.3205, longitude: -71.0520)  // JFK/UMass
            ]
        ),
        PresetRoute(
            id: "nahant-north-shore",
            name: "Nahant & North Shore",
            area: "Charlestown · Revere Beach · Lynn · Nahant",
            approxMiles: 30,
            difficulty: .moderate,
            category: .road,
            summary: "Ocean out-and-back: Charlestown Navy Yard north to Revere Beach, along Lynn Shore Drive, over the Nahant causeway to the tip of the peninsula, and back the same way. Flat and fast; can be windy. Busiest stretch is Rt 1A through Revere — ride early.",
            waypoints: [
                CLLocationCoordinate2D(latitude: 42.3730, longitude: -71.0560), // Charlestown Navy Yard
                CLLocationCoordinate2D(latitude: 42.4160, longitude: -70.9920), // Revere Beach
                CLLocationCoordinate2D(latitude: 42.4420, longitude: -70.9700), // Point of Pines
                CLLocationCoordinate2D(latitude: 42.4620, longitude: -70.9360), // Lynn Shore Dr (Red Rock)
                CLLocationCoordinate2D(latitude: 42.4190, longitude: -70.9080), // Nahant (East Point)
                CLLocationCoordinate2D(latitude: 42.4620, longitude: -70.9360), // Lynn Shore Dr
                CLLocationCoordinate2D(latitude: 42.4160, longitude: -70.9920), // Revere Beach
                CLLocationCoordinate2D(latitude: 42.3730, longitude: -71.0560)  // Charlestown Navy Yard
            ]
        )
    ]
}
