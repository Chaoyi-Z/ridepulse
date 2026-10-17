import Foundation
import AVFoundation

/// Voice-prompt preferences shared by Settings and RoutePlanner.
enum VoiceSettings {
    static let enabledKey = "voiceGuidance"
    static let identifierKey = "voiceIdentifier"
    static let rateKey = "voiceRate"

    static let defaultRate = Double(AVSpeechUtteranceDefaultSpeechRate)   // 0.5
    static let rateRange = 0.38...0.62

    /// Voices for the user's language (falls back to English), best quality first.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        var voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        if voices.isEmpty {
            voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        }
        return voices.sorted {
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            if $0.language != $1.language { return $0.language < $1.language }
            return $0.name < $1.name
        }
    }

    static func displayName(_ v: AVSpeechSynthesisVoice) -> String {
        let region = Locale.current.localizedString(forRegionCode: String(v.language.suffix(2))) ?? v.language
        let quality: String
        switch v.quality {
        case .premium: quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default: quality = ""
        }
        return "\(v.name) (\(region))\(quality)"
    }

    /// The voice to speak with: the chosen one if still installed, else the
    /// best available for the current locale, else the system default.
    static func selectedVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: identifierKey),
           let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return availableVoices().first ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
    }

    static var rate: Float {
        let stored = UserDefaults.standard.double(forKey: rateKey)
        return Float(stored > 0 ? stored : defaultRate)
    }

    /// Build an utterance with the user's voice and speed.
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = selectedVoice()
        u.rate = rate
        u.prefersAssistiveTechnologySettings = false
        return u
    }
}
