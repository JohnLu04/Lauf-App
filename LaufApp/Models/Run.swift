import Foundation
import SwiftData
import CoreLocation

/// Ein einzelner GPS-Punkt einer Aufzeichnung.
struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var timestamp: Date
    /// Wird nach jeder Pause erhöht, damit keine Linie über die Pause gezeichnet wird.
    var segment: Int

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Kilometer-Zwischenzeit.
struct Split: Codable, Hashable, Identifiable {
    var index: Int
    var distance: Double
    var duration: TimeInterval
    var elevationGain: Double
    var id: Int { index }
    /// Sekunden pro km
    var pace: Double { distance > 0 ? duration / (distance / 1000) : 0 }
}

@Model
final class Run {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// Meter
    var distance: Double = 0
    /// Sekunden ohne Pausen
    var movingTime: Double = 0
    /// Sekunden inklusive Pausen
    var elapsedTime: Double = 0
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    /// 0 = keine Angabe, sonst 1–10
    var perceivedEffort: Int = 0
    var plannedWorkoutID: UUID?
    @Attribute(.externalStorage) var routeData: Data = Data()
    var splitsData: Data = Data()
    var bestEffortsData: Data = Data()

    init(title: String, startDate: Date, endDate: Date) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Durchschnittliche Pace in Sekunden pro km.
    var averagePace: Double { distance > 0 ? movingTime / (distance / 1000) : 0 }

    var route: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: routeData)) ?? [] }
        set { routeData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var splits: [Split] {
        get { (try? JSONDecoder().decode([Split].self, from: splitsData)) ?? [] }
        set { splitsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Schnellste Zeit (Sekunden) je Distanz (Meter, gerundet) innerhalb dieses Laufs.
    var bestEfforts: [Int: Double] {
        get { (try? JSONDecoder().decode([Int: Double].self, from: bestEffortsData)) ?? [:] }
        set { bestEffortsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
