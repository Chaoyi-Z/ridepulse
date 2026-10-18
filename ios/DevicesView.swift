import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var bleManager: BLEPowerMeterManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @EnvironmentObject private var locationManager: LocationSpeedManager

    var body: some View {
        NavigationStack {
            List {
                // MARK: Power meter
                Section("Power Meter") {
                    switch bleManager.connectionState {
                    case .connected:
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(bleManager.connectedDeviceName ?? "Power Meter")
                                    .font(.headline)
                                if let watts = bleManager.powerWatts {
                                    Text("Live: \(watts) W")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Connected — spin the crank to wake it")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Disconnect") {
                                bleManager.disconnect()
                            }
                            .buttonStyle(.bordered)
                        }
                    case .connecting:
                        HStack {
                            ProgressView()
                            Text("Connecting…")
                                .foregroundStyle(.secondary)
                        }
                    case .scanning, .disconnected:
                        if bleManager.discoveredDevices.isEmpty {
                            Text("No power meters found yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(bleManager.discoveredDevices) { device in
                                Button {
                                    bleManager.connect(device)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(device.name)
                                                .foregroundStyle(.primary)
                                            Text("\(device.rssi) dBm")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                    }
                                }
                            }
                        }
                        Button(bleManager.connectionState == .scanning ? "Stop Scan" : "Scan for Power Meter") {
                            if bleManager.connectionState == .scanning {
                                bleManager.stopScan()
                            } else {
                                bleManager.startScan()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to pair")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("1. Spin the crank a few turns to wake the 4iiii (green LED blinks).\n2. Tap Scan above, then tap the meter in the list.\n3. A power meter allows only ONE Bluetooth connection — force-close the 4iiii app while using RidePulse.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Apple Watch
                Section("Apple Watch") {
                    HStack {
                        StatusDot(label: "Reachable", ok: watchManager.isReachable)
                        Spacer()
                        Text(watchManager.isReachable ? "Connected" : "Not reachable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack {
                            Text("Heart rate")
                            Spacer()
                            if let bpm = watchManager.heartRateBpm, let d = watchManager.lastHeartRateDate {
                                let age = Int(Date().timeIntervalSince(d))
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("\(Int(bpm.rounded())) bpm").font(.headline)
                                    Text(age < 15 ? "live" : "\(age)s ago — not streaming")
                                        .font(.caption2)
                                        .foregroundStyle(age < 15 ? .green : .orange)
                                }
                            } else {
                                Text("none received yet").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        watchManager.launchWatchWorkout()
                    } label: {
                        Label("Start watch workout now", systemImage: "applewatch.watchface")
                    }
                    if let status = watchManager.watchLaunchStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How it works")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Starting a ride on the iPhone now launches the watch workout automatically (keep the watch on your wrist and unlocked). You can also use “Start watch workout now” above to test it before a ride — heart rate should show “live” within ~10 seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Location
                Section("Location") {
                    HStack {
                        Text("GPS status")
                        Spacer()
                        Text(locationStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if locationManager.authorizationStatus == .notDetermined {
                        Button("Allow Location Access") {
                            locationManager.requestPermission()
                        }
                    }
                }
            }
            .navigationTitle("Devices")
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked"
        @unknown default: return "Unknown"
        }
    }
}
