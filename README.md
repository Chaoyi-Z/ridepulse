# RidePulse — iOS + watchOS Cycling Tracker

Live **power** (4iiii BLE power meter), **heart rate** (Apple Watch), and **speed/distance** (iPhone GPS),
with ride recording, saved history, route maps, charts, and GPX export. No third-party dependencies —
SwiftUI + CoreBluetooth + CoreLocation + WatchConnectivity + HealthKit + SwiftData + Charts + MapKit only.

- iOS 17+, watchOS 10+, Swift 5, Xcode 15+.

## What each target does

| Target | Responsibility |
|---|---|
| iPhone app | BLE power meter connection, GPS speed/distance, receives HR from watch, ride recording, SwiftData history, maps, charts, GPX export |
| Watch app | HealthKit cycling workout, streams live HR to iPhone via WatchConnectivity |

## Project setup in Xcode

These are source files, not an `.xcodeproj` (Xcode projects can't be authored reliably by hand).
Create the project like this:

1. **Xcode > File > New > Project… > iOS > App**
   - Product Name: `RidePulse`
   - Interface: **SwiftUI**, Language: **Swift**, Storage: **SwiftData**
   - This creates the iOS target.
2. **File > New > Target… > watchOS > Watch App**
   - Product Name: `RidePulse Watch App`
   - Language: Swift. (Xcode scaffolds a Watch App + WatchKit Extension; keep both.)
3. **Delete the template-generated source files** Xcode created for both targets
   (the default `ContentView.swift`, `RidePulseApp.swift`, etc.), then drag in
   this folder's files per the table below. When adding, check **only** the
   matching target's membership box.

### File → target mapping

| File | iOS target | watchOS target |
|---|---|---|
| `ios/RidePulseApp.swift` | ✅ | |
| `ios/Models.swift` | ✅ | |
| `ios/BLEPowerMeterManager.swift` | ✅ | |
| `ios/LocationSpeedManager.swift` | ✅ | |
| `ios/WatchConnectivityManager.swift` | ✅ | |
| `ios/RideRecorder.swift` | ✅ | |
| `ios/RideStore.swift` | ✅ | |
| `ios/ContentView.swift` | ✅ | |
| `ios/DashboardView.swift` | ✅ | |
| `ios/DevicesView.swift` | ✅ | |
| `ios/HistoryView.swift` | ✅ | |
| `ios/RideDetailView.swift` | ✅ | |
| `ios/SettingsView.swift` | ✅ | |
| `ios/PresetRoutes.swift` | ✅ | |
| `ios/RoutePlanner.swift` | ✅ | |
| `ios/RoutesView.swift` | ✅ | |
| `ios/RideStats.swift` | ✅ | |
| `watchos/RidePulseWatchApp.swift` | | ✅ |
| `watchos/WatchWorkoutManager.swift` | | ✅ |
| `watchos/WatchContentView.swift` | | ✅ |

`ios/Info-plist-keys.txt` is documentation, not a build file — add those keys
manually in each target's Info tab (details inside the file).

## Capabilities & signing

1. Select the **project** > your **Team** (a free Apple ID works).
   - Free Apple ID: apps install on your own devices but the provisioning
     certificate expires every **7 days** — re-run from Xcode to re-sign.
   - Apple Developer Program ($99/yr): no re-signing hassle, TestFlight, App Store.
2. **iOS target > Signing & Capabilities > + Capability:**
   - **Background Modes** → check **Bluetooth LE accessories** and **Location updates**.
3. **Watch target > Signing & Capabilities > + Capability:**
   - **HealthKit**.
   - **Background Modes** (WatchKit Extension) → check **Workout Processing**.
4. Add the **Info.plist keys** from `ios/Info-plist-keys.txt`
   (Bluetooth + Location usage strings on iOS; Health usage strings on watchOS).

## Install & test

1. Pair your Apple Watch to the iPhone first (Watch app on iPhone).
2. In Xcode, select the **RidePulse (iPhone)** scheme, choose your iPhone as the
   destination, and Run. Then switch to the **RidePulse Watch App** scheme,
   choose your Apple Watch, and Run. (Or run the iOS scheme and install the
   watch app via the Watch app on iPhone > Available Apps.)
3. **Power meter:** spin the crank to wake the 4iiii (green LED blinks), then in
   RidePulse go to **Devices > Scan for Power Meter** and tap it.
   ⚠️ A power meter allows **one Bluetooth connection at a time** — force-close
   the 4iiii app (and any other fitness app) while testing RidePulse.
4. **Heart rate:** open RidePulse on the **watch**, grant Health access, tap
   **Start Workout**. Live HR appears on the iPhone dashboard within seconds
   ("Watch" dot turns green).
5. **Ride:** tap **Start Ride** on the iPhone dashboard. Ride with the phone
   where it sees the sky for good GPS. **Pause** at stops, **Finish** to save.
   Find the ride under **History** — tap it for stats, route map, charts, GPX export.

## Routes & navigation

- **Routes tab:** search any address or place and get turn-by-turn directions, or pick a
  preset ride. Fourteen Boston-area routes are built in, grouped as:
  - *Paths & Greenways:* Charles River Loop (17 mi), Esplanade Short Loop (5),
    Minuteman Bikeway (10), Emerald Necklace (7), Southwest Corridor (5),
    Castle Island & Harborwalk (8), Neponset River Greenway (5).
  - *Road Rides (20–30 mi):* from Harvard Square — Weston–Lincoln Loop (27),
    Mystic Lakes & Lexington Loop (22), Newton Hills & Wellesley Loop (28);
    from Alewife — Concord & Battle Road Loop (30); farther afield —
    Blue Hills & Quincy Shore (25, climbing, from JFK/UMass), Nahant & North Shore
    (30, from Charlestown), Dover–Sherborn Loop (26, from Wellesley).

  The list shows the distance from your current location to each route's start
  and sorts nearest-first, so it's easy to spot rides you can begin from home.

  Presets are waypoint lists in `ios/PresetRoutes.swift`, snapped to real roads/paths
  via MapKit when loaded. Add your own by appending a `PresetRoute` there.
- **Turn-by-turn on the Ride screen:** next maneuver + distance, remaining distance,
  ETA at current speed, route drawn on the live map, off-route warning with automatic
  re-routing for destinations, and optional voice prompts (Settings > Navigation).
- **Full-screen navigation:** tap the map (or "Full screen" in the banner) for a
  course-up map that follows you with the route and your ridden track, the turn
  banner, live speed/power/HR/distance/time, Start/Pause/Finish controls, recenter and
  overview buttons. The screen stays awake while this view is open
  (`ios/NavigationMapView.swift`).
- **Routing network:** MapKit exposes no cycling directions to third-party apps on
  iOS 17, so in-app routes use the walking network (bike paths, trails, no highways).
  Tap **Apple Maps** in the navigation banner for Apple's cycling-specific routing.
- Code: `ios/RoutePlanner.swift` (search, directions, progress, voice),
  `ios/RoutesView.swift` (UI), `NavigationBanner` in `ios/DashboardView.swift`.

## Logo / app icon

The icon (a wheel ring with a heartbeat pulse running through it — bike + heart
rate + power) lives in `ios/Assets.xcassets/AppIcon.appiconset` and
`watchos/Assets.xcassets/AppIcon.appiconset` as single 1024×1024 PNGs. It is
generated procedurally by `design/make-icon.swift`; to tweak colours or geometry
edit that file and run:

```
swift design/make-icon.swift ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png ios
swift design/make-icon.swift watchos/Assets.xcassets/AppIcon.appiconset/AppIcon.png watch
```

`design/RidePulse-logo-1024.png` is the same mark for use outside the app.

## Live Activity, auto-pause, watch, Health & Strava

- **Lock Screen / Dynamic Island:** a Live Activity starts with every ride showing
  speed, power, HR, distance, time and — while navigating — the next turn
  (`widgets/` extension + `shared/RideActivityAttributes.swift`,
  `ios/LiveActivityController.swift`). Allow it when iOS asks the first time.
- **Auto-pause:** the clock stops after ~3 s below 2 mph and resumes when you roll
  (Settings › Recording). Averages use moving time.
- **Watch bike computer:** the watch mirrors speed / power / HR / distance / time and
  the next turn, with Start / Pause / Finish buttons that control the phone. The HR
  workout starts automatically when a ride starts.
- **GPX import & My Routes:** import `.gpx` from Files/Strava/Komoot (toolbar button
  or "Open in RidePulse"), or save any ride as a route from its detail page. Imported
  tracks are followed as-is; turns are derived from heading changes
  (`ios/GPXImporter.swift`, `ios/SavedRoute.swift`).
- **Elevation:** route pages show an elevation profile and total climb; the navigation
  banner shows the grade over the next 400 m. Elevation comes from the free
  Open-Meteo elevation API (`ios/ElevationService.swift`) — route coordinates are
  sent to that service when a route is loaded.
- **Apple Health:** finished rides are saved as outdoor cycling workouts with route,
  distance, HR, power and estimated calories (`ios/HealthExporter.swift`;
  Settings › Apple Health to disable).
- **Strava:** connect once (Settings › Strava, using your own free API app from
  strava.com/settings/api with callback domain `localhost`), then upload from any
  ride's page or enable auto-upload (`ios/StravaService.swift`). Tokens are kept in
  the Keychain.

## Features

- **Dashboard:** live Power (W), Heart Rate (bpm), Speed (mph/km/h), Cadence (rpm),
  **Distance** and **active Duration** as primary tiles; live GPS route map while
  recording; start/pause/resume/finish/discard controls; connection dots.
- **Devices:** BLE scan/connect for the power meter, watch reachability, pairing hints.
- **History:** past rides with distance, duration, avg power; swipe to delete.
- **Post-ride summary:** a "Ride Complete" sheet appears when you tap Finish with
  headline stats plus derived statistics computed from the samples
  (`ios/RideStats.swift`): elapsed vs moving vs stopped time, elevation gain/loss,
  normalized power, variability index, work (kJ), estimated calories, peak power
  for 5 s / 1 min / 5 min / 20 min, and time in zones. Set **FTP** and **max HR**
  under Settings › Rider Profile to get Coggan power zones (Z1–Z7), Intensity
  Factor, TSS and 5-zone heart-rate distribution; without FTP the summary falls
  back to easy/steady/hard bands relative to the ride average. The same stats
  show on every ride in History.
- **Ride detail:** summary stats, full route map with start/end markers,
  power/HR/speed charts, GPX export (ShareLink).
- **Settings:** mph ↔ km/h toggle, rider profile (FTP, max HR), voice turn prompts with a choice of engine — Azure neural TTS (your own Speech key/region, prompts pre-synthesized and cached per route, `ios/VoiceEngine.swift`) or on-device Apple voices with picker and speed (`ios/VoiceSettings.swift`) — plus preview, 4iiii zero-offset calibration reminder.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Power meter not found in scan | Spin crank to wake it; move closer; make sure no other app/device is connected to it (BLE = one connection) |
| Power shows "--" after connecting | The meter sleeps quickly — spin the crank; values appear once it transmits |
| No heart rate on iPhone | Start the workout on the watch; keep the watch app in the foreground at first; check the "Phone linked" dot on the watch |
| GPS speed stuck at 0 | Allow Location access (Devices tab shows status); go outdoors; "Always" allows background tracking when the screen locks |
| Watch HR stops mid-ride | watchOS may suspend the app — the HKWorkoutSession keeps it alive; if it drops, reopen the watch app |
| Build error about HealthKit | Enable the HealthKit capability on the **watchOS** target, not iOS |

## Notes / assumptions

- SwiftData `@Model` classes with cascade-delete samples; no CloudKit sync in v1.
- Speed comes from GPS (`CLLocation.speed`); the power meter does not provide speed.
- Heart rate requires the watch workout — the phone never reads HR directly.
- Charts put power/HR/speed on one axis for simplicity (v1).
- Written against Swift 5 language mode / Xcode 15 SDKs (iOS 17, watchOS 10).
