import Foundation
import AVFoundation
import CryptoKit
import Security

/// Speaks navigation prompts with either Azure neural TTS (fetched once per
/// sentence and cached on disk, so prompts play instantly offline) or the
/// on-device Apple voice. Azure is used whenever a key is configured and the
/// sentence is cached or the network answers quickly; otherwise Apple speaks.
@MainActor
final class VoiceEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoiceEngine()

    static let engineKey = "voiceEngine"            // "azure" | "apple"
    static let azureVoiceKey = "azureVoice"
    static let azureRegionKey = "azureRegion"
    private static let keychainAccount = "azure-speech-key"

    struct AzureVoice: Identifiable, Hashable {
        let id: String      // short name, e.g. en-US-AvaMultilingualNeural
        let label: String
    }

    static let azureVoices: [AzureVoice] = [
        .init(id: "en-US-AvaMultilingualNeural",    label: "Ava (US)"),
        .init(id: "en-US-EmmaMultilingualNeural",   label: "Emma (US)"),
        .init(id: "en-US-AndrewMultilingualNeural", label: "Andrew (US)"),
        .init(id: "en-US-BrianMultilingualNeural",  label: "Brian (US)"),
        .init(id: "en-US-JennyNeural",              label: "Jenny (US)"),
        .init(id: "en-US-GuyNeural",                label: "Guy (US)"),
        .init(id: "en-US-AriaNeural",               label: "Aria (US)"),
        .init(id: "en-GB-SoniaNeural",              label: "Sonia (UK)"),
        .init(id: "en-GB-RyanNeural",               label: "Ryan (UK)")
    ]

    @Published private(set) var lastError: String?
    @Published private(set) var cachedCount = 0

    private let apple = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var queue: [URL] = []
    private var inFlight: Set<String> = []

    // MARK: - Configuration

    static var engine: String {
        UserDefaults.standard.string(forKey: engineKey) ?? "azure"
    }
    static var azureVoice: String {
        UserDefaults.standard.string(forKey: azureVoiceKey) ?? azureVoices[0].id
    }
    static var azureRegion: String {
        (UserDefaults.standard.string(forKey: azureRegionKey) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }
    static var azureKey: String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: keychainAccount,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }
    static func setAzureKey(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: keychainAccount]
        SecItemDelete(q as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static var azureConfigured: Bool { azureKey != nil && !azureRegion.isEmpty }
    static var usesAzure: Bool { engine == "azure" && azureConfigured }

    // MARK: - Speaking

    /// Speak `text`. Azure if configured (cached → instant; otherwise fetched,
    /// falling back to Apple if the fetch fails or takes > 1.5 s).
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        activateAudioSession()
        guard Self.usesAzure else { speakApple(text); return }

        if let url = cachedURL(for: text), FileManager.default.fileExists(atPath: url.path) {
            play(url)
            return
        }
        Task {
            let result = await withTimeout(seconds: 1.5) { await self.synthesize(text) }
            if let url = result { self.play(url) } else { self.speakApple(text) }
        }
    }

    func stop() {
        apple.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        queue.removeAll()
    }

    /// Fetch and cache every sentence so they play instantly on the road.
    func prefetch(_ sentences: [String]) {
        guard Self.usesAzure else { return }
        Task {
            for s in Set(sentences) where !s.isEmpty {
                if let url = cachedURL(for: s), FileManager.default.fileExists(atPath: url.path) { continue }
                _ = await synthesize(s)
            }
            cachedCount = (try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path).count) ?? 0
        }
    }

    /// Test the current Azure key/region with a short sentence.
    func testAzure() async -> String {
        guard Self.azureConfigured else { return "Enter the Azure key and region first." }
        lastError = nil
        if let url = await synthesize("Azure neural voice is ready.") {
            activateAudioSession()
            play(url)
            return "Azure works — \(Self.azureVoices.first { $0.id == Self.azureVoice }?.label ?? Self.azureVoice)."
        }
        return lastError ?? "Azure request failed."
    }

    // MARK: - Azure REST

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cachedURL(for text: String) -> URL? {
        let key = "\(Self.azureVoice)|\(text)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hash).mp3")
    }

    private func synthesize(_ text: String) async -> URL? {
        guard let key = Self.azureKey, !Self.azureRegion.isEmpty, let url = cachedURL(for: text) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return url }
        if inFlight.contains(text) { return nil }
        inFlight.insert(text)
        defer { inFlight.remove(text) }

        let voice = Self.azureVoice
        let lang = String(voice.prefix(5))
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let ssml = """
        <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="\(lang)">\
        <voice name="\(voice)"><prosody rate="+5%">\(escaped)</prosody></voice></speak>
        """
        var req = URLRequest(url: URL(string: "https://\(Self.azureRegion).tts.speech.microsoft.com/cognitiveservices/v1")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        req.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        req.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        req.setValue("RidePulse", forHTTPHeaderField: "User-Agent")
        req.httpBody = ssml.data(using: .utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, code == 200, data.count > 500 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                lastError = code == 401 ? "Azure rejected the key (401). Check key and region."
                         : code == 400 ? "Azure rejected the request (400)." : "Azure error \(code)."
                return nil
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            lastError = "Azure: \(error.localizedDescription)"
            return nil
        }
    }

    private func withTimeout<T>(seconds: Double, _ op: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Playback

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func speakApple(_ text: String) {
        apple.speak(VoiceSettings.utterance(text))
    }

    private func play(_ url: URL) {
        if let player, player.isPlaying {
            queue.append(url)     // don't talk over ourselves; play after the current prompt
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
        } catch {
            lastError = "Playback failed: \(error.localizedDescription)"
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            if !self.queue.isEmpty { self.play(self.queue.removeFirst()) }
        }
    }
}
