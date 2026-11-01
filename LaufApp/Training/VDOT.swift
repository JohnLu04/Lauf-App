import Foundation

/// Trainingspaces in Sekunden pro km.
struct TrainingPaces: Codable, Hashable {
    var easySlow: Double
    var easyFast: Double
    var marathon: Double
    var threshold: Double
    var interval: Double
    var repetition: Double
}

/// VDOT-Modell nach Jack Daniels ("Daniels' Running Formula").
/// Aus einer Wettkampfzeit wird ein Leistungswert (VDOT) berechnet,
/// aus dem sich Trainingspaces und Zeitprognosen ableiten.
enum VDOT {
    /// Sauerstoffbedarf (ml/kg/min) bei Geschwindigkeit v (m/min).
    static func oxygenCost(velocity v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Anteil der VO2max, der über eine Dauer von t Minuten gehalten werden kann.
    static func fractionOfMax(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    static func vdot(distance: Double, time: TimeInterval) -> Double {
        guard distance > 0, time > 0 else { return 0 }
        let minutes = time / 60
        return oxygenCost(velocity: distance / minutes) / fractionOfMax(minutes: minutes)
    }

    /// Geschwindigkeit (m/min), die einem Sauerstoffverbrauch entspricht.
    static func velocity(forVO2 vo2: Double) -> Double {
        let a = 0.000104, b = 0.182258, c = -4.60 - vo2
        return (-b + sqrt(b * b - 4 * a * c)) / (2 * a)
    }

    static func pace(forVO2 vo2: Double) -> Double {
        1000 / velocity(forVO2: vo2) * 60
    }

    /// Prognostizierte Wettkampfzeit (Sekunden) für eine Distanz bei gegebenem VDOT.
    static func predictTime(distance: Double, vdot target: Double) -> TimeInterval {
        var lo = 60.0, hi = 60.0 * 60 * 12
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            // Mehr Zeit → niedrigerer VDOT
            if vdot(distance: distance, time: mid) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    static func paces(vdot v: Double) -> TrainingPaces {
        TrainingPaces(
            easySlow: pace(forVO2: v * 0.62),
            easyFast: pace(forVO2: v * 0.70),
            marathon: predictTime(distance: 42195, vdot: v) / 42.195,
            threshold: pace(forVO2: v * 0.88),
            interval: pace(forVO2: v * 0.975),
            repetition: pace(forVO2: v * 1.05)
        )
    }
}
