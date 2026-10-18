import Foundation
import SwiftUI

/// Rider profile values stored in UserDefaults (edited in Settings).
enum RiderProfile {
    static let ftpKey = "ftpWatts"
    static let maxHRKey = "maxHeartRateBpm"
    static let weightKey = "weightKg"
    static let ageKey = "ageYears"
    static let sexKey = "biologicalSex"      // "", "male", "female"

    static var ftp: Int? {
        let v = UserDefaults.standard.integer(forKey: ftpKey)
        return v > 0 ? v : nil
    }

    static var maxHR: Int? {
        let v = UserDefaults.standard.integer(forKey: maxHRKey)
        return v > 0 ? v : nil
    }

    static var weightKg: Double? {
        let v = UserDefaults.standard.double(forKey: weightKey)
        return v > 0 ? v : nil
    }

    static var age: Int? {
        let v = UserDefaults.standard.integer(forKey: ageKey)
        return v > 0 ? v : nil
    }

    static var sex: String { UserDefaults.standard.string(forKey: sexKey) ?? "" }
}

/// Where a ride's calorie figure came from.
enum CalorieSource: String {
    case power = "power meter"
    case heartRate = "heart rate"
    case speed = "speed"
}

/// One training zone bucket with time spent in it.
struct ZoneTime: Identifiable {
    let id: Int
    let name: String
    let range: String
    let seconds: TimeInterval
    let color: Color
}

/// Derived statistics computed from a ride's 1 Hz samples. Everything here is
/// calculated on demand from `RideSample`s, so older rides get the new stats too.
struct RideStats {
    let elapsedSeconds: TimeInterval
    let movingSeconds: TimeInterval
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    /// Coggan normalized power (30 s rolling average, 4th-power mean). nil without power data.
    let normalizedPower: Double?
    /// Mechanical work in kilojoules (sum of watts × seconds / 1000).
    let workKilojoules: Double?
    /// Rough calories: kJ ≈ kcal for cycling (~24% efficiency cancels the 4.184 factor).
    let estimatedCalories: Double?
    /// What the calorie estimate was based on (most accurate available).
    let calorieSource: CalorieSource?
    /// True when weight/age/sex weren't known and defaults were used.
    let calorieUsedDefaults: Bool
    /// Variability index NP / avg power. ~1.0 = steady, >1.1 = surgy.
    let variabilityIndex: Double?
    /// Intensity factor NP / FTP (needs FTP).
    let intensityFactor: Double?
    /// Training Stress Score (needs FTP).
    let tss: Double?
    /// Best average power over common durations.
    let peakPower: [(seconds: Int, watts: Int)]
    /// Power zones: Coggan Z1–Z7 when FTP is set, otherwise 3 bands relative to ride average.
    let powerZones: [ZoneTime]
    let powerZonesUseFTP: Bool
    /// Heart-rate zones Z1–Z5 as % of max HR (needs max HR and HR data).
    let heartRateZones: [ZoneTime]

    static let peakWindows = [5, 60, 300, 1200]

    init(ride: Ride, ftp: Int? = RiderProfile.ftp, maxHR: Int? = RiderProfile.maxHR,
         weightKg: Double? = RiderProfile.weightKg, age: Int? = RiderProfile.age,
         sex: String = RiderProfile.sex) {
        let samples = ride.samples.sorted { $0.timestamp < $1.timestamp }
        elapsedSeconds = max(0, ride.endDate.timeIntervalSince(ride.startDate))
        movingSeconds = ride.durationSeconds

        // Elevation: smooth with a 5-sample moving average and ignore tiny jitter.
        let alts = samples.compactMap { $0.altitude }
        var gain = 0.0, loss = 0.0
        if alts.count > 5 {
            var smoothed: [Double] = []
            for i in 0..<alts.count {
                let lo = max(0, i - 2), hi = min(alts.count - 1, i + 2)
                smoothed.append(alts[lo...hi].reduce(0, +) / Double(hi - lo + 1))
            }
            var last = smoothed[0]
            for a in smoothed.dropFirst() {
                let d = a - last
                if abs(d) >= 1.0 {          // 1 m threshold filters GPS noise
                    if d > 0 { gain += d } else { loss -= d }
                    last = a
                }
            }
        }
        elevationGainMeters = gain
        elevationLossMeters = loss

        // Power-derived stats (samples are ~1 s apart; treat each as 1 s).
        let powers = samples.map { Double($0.powerWatts ?? 0) }
        let hasPower = samples.contains { $0.powerWatts != nil }
        if hasPower, !powers.isEmpty {
            let kj = powers.reduce(0, +) / 1000.0
            workKilojoules = kj

            // Normalized power
            var np: Double?
            if powers.count >= 30 {
                var rolling: [Double] = []
                var window = 0.0
                for (i, p) in powers.enumerated() {
                    window += p
                    if i >= 30 { window -= powers[i - 30] }
                    if i >= 29 { rolling.append(window / 30.0) }
                }
                let mean4 = rolling.map { pow($0, 4) }.reduce(0, +) / Double(rolling.count)
                np = pow(mean4, 0.25)
            }
            normalizedPower = np
            variabilityIndex = (np != nil && ride.avgPowerWatts > 0) ? np! / ride.avgPowerWatts : nil

            // IF / TSS
            if let np, let ftp, ftp > 0 {
                let iff = np / Double(ftp)
                intensityFactor = iff
                tss = (Double(powers.count) * np * iff) / (Double(ftp) * 3600.0) * 100.0
            } else {
                intensityFactor = nil
                tss = nil
            }

            // Peak powers
            var peaks: [(Int, Int)] = []
            var prefix: [Double] = [0]
            prefix.reserveCapacity(powers.count + 1)
            for p in powers { prefix.append(prefix.last! + p) }
            for w in Self.peakWindows where powers.count >= w {
                var best = 0.0
                for i in w...powers.count {
                    best = max(best, (prefix[i] - prefix[i - w]) / Double(w))
                }
                peaks.append((w, Int(best.rounded())))
            }
            peakPower = peaks

            // Power zones
            if let ftp, ftp > 0 {
                powerZonesUseFTP = true
                powerZones = Self.cogganZones(powers: powers, ftp: Double(ftp))
            } else {
                powerZonesUseFTP = false
                let avg = max(ride.avgPowerWatts, 1)
                var easy = 0.0, steady = 0.0, hard = 0.0
                for p in powers {
                    switch p / avg {
                    case ..<0.75: easy += 1
                    case ..<1.25: steady += 1
                    default: hard += 1
                    }
                }
                powerZones = [
                    ZoneTime(id: 1, name: "Easy", range: "<75% of avg", seconds: easy, color: .gray),
                    ZoneTime(id: 2, name: "Steady", range: "75–125% of avg", seconds: steady, color: .blue),
                    ZoneTime(id: 3, name: "Hard", range: ">125% of avg", seconds: hard, color: .red)
                ]
            }
        } else {
            workKilojoules = nil
            normalizedPower = nil
            variabilityIndex = nil
            intensityFactor = nil
            tss = nil
            peakPower = []
            powerZones = []
            powerZonesUseFTP = false
        }

        // Calories: power meter (mechanical work ≈ kcal for cycling) > heart rate > speed.
        let hoursMoving = max(ride.durationSeconds, 0) / 3600
        let minutesMoving = hoursMoving * 60
        let hrSamples = samples.compactMap { $0.heartRateBpm }.map(Double.init)
        let knownWeight = weightKg
        let weight = knownWeight ?? 70
        var kcal: Double?
        var source: CalorieSource?
        var usedDefaults = false

        if let kj = workKilojoules, kj > 0 {
            kcal = kj
            source = .power
        } else if !hrSamples.isEmpty, minutesMoving > 0 {
            // Keytel et al. (2005) heart-rate equation, kcal/min; subtract resting (~1 MET)
            // so the figure is *active* energy, which is what the Move ring counts.
            let hr = hrSamples.reduce(0, +) / Double(hrSamples.count)
            let a = Double(age ?? 35)
            let male = (-55.0969 + 0.6309 * hr + 0.1988 * weight + 0.2017 * a) / 4.184
            let female = (-20.4022 + 0.4472 * hr - 0.1263 * weight + 0.074 * a) / 4.184
            let perMinute: Double
            switch sex {
            case "male": perMinute = male
            case "female": perMinute = female
            default: perMinute = (male + female) / 2
            }
            let resting = 0.01667 * weight          // 1 MET ≈ 1 kcal/kg/h
            kcal = max(0, (perMinute - resting) * minutesMoving)
            source = .heartRate
            usedDefaults = knownWeight == nil || age == nil || sex.isEmpty
        } else if hoursMoving > 0, ride.avgSpeedMps > 0 {
            // Compendium of Physical Activities cycling METs by speed.
            let mph = ride.avgSpeedMps * 2.23694
            let met: Double
            switch mph {
            case ..<10: met = 4.0
            case ..<12: met = 6.8
            case ..<14: met = 8.0
            case ..<16: met = 10.0
            case ..<19: met = 12.0
            default: met = 15.8
            }
            kcal = max(0, (met - 1) * weight * hoursMoving)
            source = .speed
            usedDefaults = knownWeight == nil
        }
        estimatedCalories = kcal
        calorieSource = source
        calorieUsedDefaults = usedDefaults

        // Heart-rate zones (% of max HR)
        let hrs = samples.compactMap { $0.heartRateBpm }.map(Double.init)
        if let maxHR, maxHR > 0, !hrs.isEmpty {
            heartRateZones = Self.hrZones(heartRates: hrs, maxHR: Double(maxHR))
        } else {
            heartRateZones = []
        }
    }

    // MARK: - Zone tables

    /// Coggan 7-zone model as % of FTP.
    private static func cogganZones(powers: [Double], ftp: Double) -> [ZoneTime] {
        let defs: [(String, String, ClosedRange<Double>, Color)] = [
            ("Z1 Recovery",  "<55%",     0.00...0.55, .gray),
            ("Z2 Endurance", "55–75%",   0.55...0.75, .blue),
            ("Z3 Tempo",     "75–90%",   0.75...0.90, .green),
            ("Z4 Threshold", "90–105%",  0.90...1.05, .yellow),
            ("Z5 VO2max",    "105–120%", 1.05...1.20, .orange),
            ("Z6 Anaerobic", "120–150%", 1.20...1.50, .red),
            ("Z7 Sprint",    ">150%",    1.50...99.0, .purple)
        ]
        var counts = [Double](repeating: 0, count: defs.count)
        for p in powers {
            let r = p / ftp
            let idx = defs.lastIndex { r >= $0.2.lowerBound } ?? 0
            counts[idx] += 1
        }
        return defs.enumerated().map { i, d in
            ZoneTime(id: i + 1, name: d.0, range: "\(d.1) FTP", seconds: counts[i], color: d.3)
        }
    }

    /// 5-zone HR model as % of max HR.
    private static func hrZones(heartRates: [Double], maxHR: Double) -> [ZoneTime] {
        let defs: [(String, String, Double, Color)] = [
            ("Z1 Easy",      "<60%",   0.00, .gray),
            ("Z2 Fat burn",  "60–70%", 0.60, .blue),
            ("Z3 Aerobic",   "70–80%", 0.70, .green),
            ("Z4 Threshold", "80–90%", 0.80, .orange),
            ("Z5 Max",       ">90%",   0.90, .red)
        ]
        var counts = [Double](repeating: 0, count: defs.count)
        for h in heartRates {
            let r = h / maxHR
            let idx = defs.lastIndex { r >= $0.2 } ?? 0
            counts[idx] += 1
        }
        return defs.enumerated().map { i, d in
            ZoneTime(id: i + 1, name: d.0, range: "\(d.1) max HR", seconds: counts[i], color: d.3)
        }
    }

    static func windowLabel(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60) min"
        default: return "\(seconds / 3600) h"
        }
    }
}
