import Foundation
import CoreLocation

enum Geo {
    /// Entfernung zweier Koordinaten in Metern (Haversine).
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        distance(a.latitude, a.longitude, b.latitude, b.longitude)
    }
}

/// Höhenmeter-Zähler mit Hysterese, damit GPS-Rauschen nicht als Anstieg zählt.
struct ElevationTracker {
    var threshold: Double = 3
    private(set) var gain: Double = 0
    private(set) var loss: Double = 0
    private var reference: Double?

    mutating func add(_ altitude: Double?) {
        guard let altitude else { return }
        guard let ref = reference else { reference = altitude; return }
        let diff = altitude - ref
        if diff >= threshold {
            gain += diff
            reference = altitude
        } else if diff <= -threshold {
            loss += -diff
            reference = altitude
        }
    }

    mutating func resetCounters() { gain = 0; loss = 0 }
}
