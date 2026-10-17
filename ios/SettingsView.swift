import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    @AppStorage("voiceGuidance") private var voiceGuidance: Bool = true
    @AppStorage(RideRecorder.autoPauseKey) private var autoPause: Bool = true
    @AppStorage(VoiceSettings.identifierKey) private var voiceIdentifier: String = ""
    @AppStorage(VoiceSettings.rateKey) private var voiceRate: Double = VoiceSettings.defaultRate
    @EnvironmentObject private var planner: RoutePlanner
    @EnvironmentObject private var strava: StravaService
    @AppStorage(HealthExporter.enabledKey) private var saveToHealth: Bool = true
    @AppStorage(StravaService.clientIDKey) private var stravaClientID: String = ""
    @AppStorage(StravaService.clientSecretKey) private var stravaClientSecret: String = ""
    @AppStorage(StravaService.autoUploadKey) private var stravaAutoUpload: Bool = false
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @AppStorage(VoiceEngine.engineKey) private var voiceEngine: String = "azure"
    @AppStorage(VoiceEngine.azureVoiceKey) private var azureVoice: String = VoiceEngine.azureVoices[0].id
    @AppStorage(VoiceEngine.azureRegionKey) private var azureRegion: String = ""
    @State private var azureKeyField: String = VoiceEngine.azureKey ?? ""
    @State private var azureStatus: String?
    @State private var testingAzure = false
    @AppStorage(RiderProfile.ftpKey) private var ftpWatts: Int = 0
    @AppStorage(RiderProfile.maxHRKey) private var maxHRBpm: Int = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Units") {
                    Picker("Speed & Distance", selection: $speedUnitRaw) {
                        Text("Miles / mph").tag(SpeedUnit.mph.rawValue)
                        Text("Kilometers / km/h").tag(SpeedUnit.kmh.rawValue)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("FTP")
                        Spacer()
                        TextField("e.g. 220", value: optionalInt($ftpWatts), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("W").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Max heart rate")
                        Spacer()
                        TextField("e.g. 185", value: optionalInt($maxHRBpm), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("bpm").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Rider Profile")
                } footer: {
                    Text("FTP (Functional Threshold Power) unlocks Coggan power zones, Intensity Factor and TSS in ride summaries. A 20-minute all-out test × 0.95 is a good estimate. Max HR enables heart-rate zones; 220 − age is a rough starting point.")
                }

                Section {
                    Toggle("Auto-pause when stopped", isOn: $autoPause)
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Pauses the ride clock automatically after ~3 seconds below 2 mph (traffic lights, stops) and resumes when you roll again. Distance keeps counting; averages use moving time only.")
                }

                Section {
                    Toggle("Voice turn prompts", isOn: $voiceGuidance)
                    if voiceGuidance {
                        Picker("Engine", selection: $voiceEngine) {
                            Text("Azure neural").tag("azure")
                            Text("Apple (offline)").tag("apple")
                        }
                        .pickerStyle(.segmented)

                        if voiceEngine == "azure" {
                            Picker("Voice", selection: $azureVoice) {
                                ForEach(VoiceEngine.azureVoices) { v in Text(v.label).tag(v.id) }
                            }
                            SecureField("Azure Speech key", text: $azureKeyField)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: azureKeyField) { _, v in VoiceEngine.setAzureKey(v) }
                            TextField("Region (e.g. eastus)", text: $azureRegion)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                testingAzure = true
                                Task { azureStatus = await VoiceEngine.shared.testAzure(); testingAzure = false }
                            } label: {
                                Label(testingAzure ? "Testing…" : "Test Azure voice", systemImage: "waveform")
                            }
                            .disabled(testingAzure || azureKeyField.isEmpty || azureRegion.isEmpty)
                            if let azureStatus {
                                Text(azureStatus).font(.caption).foregroundStyle(.secondary)
                            }
                            if !VoiceEngine.azureConfigured {
                                Text("Until a key and region are entered, prompts use the Apple voice below.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }

                        Picker(voiceEngine == "azure" ? "Apple fallback voice" : "Voice", selection: $voiceIdentifier) {
                            Text("Automatic").tag("")
                            ForEach(voices, id: \.identifier) { v in
                                Text(VoiceSettings.displayName(v)).tag(v.identifier)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Apple speaking speed")
                                Spacer()
                                Text(voiceRate < 0.47 ? "Slower" : voiceRate > 0.53 ? "Faster" : "Normal")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $voiceRate, in: VoiceSettings.rateRange) {
                                Text("Speaking speed")
                            } minimumValueLabel: {
                                Image(systemName: "tortoise").font(.caption)
                            } maximumValueLabel: {
                                Image(systemName: "hare").font(.caption)
                            }
                        }
                        Button {
                            planner.previewVoice()
                        } label: {
                            Label("Preview voice", systemImage: "speaker.wave.2.fill")
                        }
                    }
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Azure neural uses your own Azure Speech resource (free tier: 500k characters/month). Every prompt for a route is fetched once when the route loads and cached, so it plays instantly and offline on the ride; anything uncached falls back to the Apple voice. For a better Apple voice, download a Premium one in iOS Settings › Accessibility › Spoken Content › Voices › English.")
                }

                Section {
                    Toggle("Save rides to Apple Health", isOn: $saveToHealth)
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Each finished ride is saved as an outdoor cycling workout with route, distance, heart rate, power and estimated calories, so it appears in Fitness and closes your rings.")
                }

                Section {
                    if strava.isConnected {
                        HStack {
                            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Text(strava.athleteName ?? "").foregroundStyle(.secondary)
                        }
                        Toggle("Auto-upload after each ride", isOn: $stravaAutoUpload)
                        Button("Disconnect", role: .destructive) { strava.disconnect() }
                    } else {
                        TextField("Client ID", text: $stravaClientID)
                            .keyboardType(.numberPad)
                        SecureField("Client Secret", text: $stravaClientSecret)
                            .textInputAutocapitalization(.never)
                        Button {
                            strava.connect()
                        } label: {
                            Label("Connect Strava", systemImage: "link")
                        }
                        .disabled(stravaClientID.isEmpty || stravaClientSecret.isEmpty || strava.isBusy)
                    }
                    if let msg = strava.statusMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Strava")
                } footer: {
                    Text("One-time setup: at strava.com/settings/api create an app (any name, Authorization Callback Domain: localhost), then paste its Client ID and Client Secret here and tap Connect. Rides upload as GPX with heart rate and power.")
                }

                Section("Power Meter") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zero-offset / calibration")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("For accurate power readings, do a zero-offset (calibration) in the 4iiii app before rides: wake the meter by spinning the crank, connect in the 4iiii app, and run the calibration with no weight on the pedals. RidePulse does not calibrate the meter itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tips")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("• A power meter allows only one Bluetooth connection at a time — force-close the 4iiii app while riding with RidePulse.\n• Start the workout on your Apple Watch to stream heart rate to the iPhone.\n• Keep the iPhone where it has a clear sky view for best GPS accuracy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .onAppear { voices = VoiceSettings.availableVoices() }
        }
    }

    /// Show the placeholder (not "0") when a profile value is unset.
    private func optionalInt(_ source: Binding<Int>) -> Binding<Int?> {
        Binding<Int?>(
            get: { source.wrappedValue > 0 ? source.wrappedValue : nil },
            set: { source.wrappedValue = max(0, $0 ?? 0) }
        )
    }
}
