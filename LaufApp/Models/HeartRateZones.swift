import Foundation

/// Fünf Herzfrequenzzonen in Prozent der maximalen Herzfrequenz.
enum HeartRateZones {
    struct Zone: Identifiable {
        let index: Int
        let name: String
        let lower: Double   // Anteil der max. HF
        let upper: Double
        var id: Int { index }
    }

    static let zones: [Zone] = [
        Zone(index: 1, name: "Regeneration", lower: 0.50, upper: 0.60),
        Zone(index: 2, name: "Grundlage", lower: 0.60, upper: 0.70),
        Zone(index: 3, name: "Tempo", lower: 0.70, upper: 0.80),
        Zone(index: 4, name: "Schwelle", lower: 0.80, upper: 0.90),
        Zone(index: 5, name: "Maximal", lower: 0.90, upper: 1.00),
    ]

    static let maxHeartRateKey = "maxHeartRate"

    /// Eingestellte maximale Herzfrequenz, sonst der höchste gemessene Wert, sonst 190.
    static func maxHeartRate(runs: [Run]) -> Double {
        let stored = UserDefaults.standard.double(forKey: maxHeartRateKey)
        if stored > 0 { return stored }
        let observed = runs.map(\.maxHeartRate).max() ?? 0
        return observed >= 150 ? observed : 190
    }

    /// Zeit (Sekunden) je Zone; Werte unter Zone 1 zählen zu Zone 1, über dem Maximum zu Zone 5.
    static func timeInZones(_ samples: [SensorSample], maxHeartRate: Double) -> [TimeInterval] {
        var result = [TimeInterval](repeating: 0, count: zones.count)
        guard maxHeartRate > 0 else { return result }
        for (prev, cur) in zip(samples, samples.dropFirst()) {
            guard let hr = cur.heartRate, hr > 0 else { continue }
            let dt = cur.time - prev.time
            guard dt > 0, dt < 30 else { continue }   // Lücken (Pausen) nicht mitzählen
            let fraction = hr / maxHeartRate
            let index = zones.lastIndex { fraction >= $0.lower } ?? 0
            result[index] += dt
        }
        return result
    }
}
