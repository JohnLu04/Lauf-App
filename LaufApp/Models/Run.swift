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

/// Messwerte einer Uhr zu einem Zeitpunkt des Laufs (z. B. von Garmin über Strava).
struct SensorSample: Codable, Hashable {
    /// Kumulierte Distanz in Metern
    var distance: Double
    /// Bewegungszeit seit dem Start in Sekunden
    var time: Double
    /// Herzfrequenz in Schlägen pro Minute
    var heartRate: Double?
    /// Schrittfrequenz in Schritten pro Minute
    var cadence: Double?

    enum CodingKeys: String, CodingKey {
        case distance = "d", time = "t", heartRate = "hr", cadence = "c"
    }
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
    /// Herkunft: "" = mit der App aufgezeichnet, "strava" = von Strava importiert
    var source: String = ""
    var stravaID: Int?
    /// Schläge pro Minute, 0 = keine Daten
    var averageHeartRate: Double = 0
    var maxHeartRate: Double = 0
    /// Schritte pro Minute, 0 = keine Daten
    var averageCadence: Double = 0
    /// Bewusst ohne `.externalStorage`: Ein neues Attribut mit externer Speicherung lässt sich
    /// nicht per Lightweight-Migration ergänzen ("Cannot migrate store in-place").
    var sensorData: Data = Data()
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

    var sensorSamples: [SensorSample] {
        get { (try? JSONDecoder().decode([SensorSample].self, from: sensorData)) ?? [] }
        set { sensorData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var isFromStrava: Bool { source == "strava" }

    /// Schnellste Zeit (Sekunden) je Distanz (Meter, gerundet) innerhalb dieses Laufs.
    var bestEfforts: [Int: Double] {
        get { (try? JSONDecoder().decode([Int: Double].self, from: bestEffortsData)) ?? [:] }
        set { bestEffortsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
