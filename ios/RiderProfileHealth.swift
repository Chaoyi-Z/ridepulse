import Foundation
import HealthKit

extension RiderProfile {
    /// Read weight, age and sex from Apple Health into the rider profile. Fields
    /// Health doesn't have are left as they are, so manual entries survive.
    /// Returns true if at least one value was found.
    @MainActor
    @discardableResult
    static func importFromHealth(requestAccess: Bool = true) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()
        let weightType = HKQuantityType(.bodyMass)
        let read: Set<HKObjectType> = [
            weightType,
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex)
        ]
        if requestAccess {
            try? await store.requestAuthorization(toShare: [], read: read)
        }
        let defaults = UserDefaults.standard
        var found = false

        // Age
        if let comps = try? store.dateOfBirthComponents(),
           let dob = Calendar.current.date(from: comps),
           let years = Calendar.current.dateComponents([.year], from: dob, to: Date()).year, years > 0 {
            defaults.set(years, forKey: ageKey)
            found = true
        }

        // Sex
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male: defaults.set("male", forKey: sexKey); found = true
            case .female: defaults.set("female", forKey: sexKey); found = true
            default: break
            }
        }

        // Most recent body-mass sample
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: weightType)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        if let sample = try? await descriptor.result(for: store).first {
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            if kg > 20, kg < 300 {
                defaults.set(kg, forKey: weightKey)
                found = true
            }
        }
        return found
    }
}
