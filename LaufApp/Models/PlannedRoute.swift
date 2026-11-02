import Foundation
import SwiftData
import CoreLocation

/// Einzelne Koordinate einer geplanten Route.
struct RouteCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    func distance(to other: RouteCoordinate) -> Double {
        Geo.distance(latitude, longitude, other.latitude, other.longitude)
    }
}

/// Gespeicherte, selbst geplante Laufstrecke.
@Model
final class PlannedRoute {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// Gesetzte Wegpunkte (zum späteren Bearbeiten)
    var waypointsData: Data = Data()
    /// Vollständiger Streckenverlauf (Wegpunkte entlang der Wege verbunden)
    var pathData: Data = Data()
    /// Meter
    var distance: Double = 0
    /// true = Strecke folgt Wegen, false = Luftlinie zwischen den Wegpunkten
    var followsPaths: Bool = true
    /// Höhenmeter bergauf/bergab (0 = noch nicht berechnet, siehe `hasElevation`)
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    /// Höhenprofil als JSON (ohne .externalStorage, damit die Migration klappt)
    var elevationData: Data = Data()

    init(name: String, waypoints: [RouteCoordinate], path: [RouteCoordinate], followsPaths: Bool) {
        self.name = name
        self.waypoints = waypoints
        self.path = path
        self.followsPaths = followsPaths
        self.distance = RouteGeometry.length(path)
    }

    var waypoints: [RouteCoordinate] {
        get { (try? JSONDecoder().decode([RouteCoordinate].self, from: waypointsData)) ?? [] }
        set { waypointsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var path: [RouteCoordinate] {
        get { (try? JSONDecoder().decode([RouteCoordinate].self, from: pathData)) ?? [] }
        set {
            pathData = (try? JSONEncoder().encode(newValue)) ?? Data()
            distance = RouteGeometry.length(newValue)
            elevation = nil
        }
    }

    var elevation: ElevationProfile? {
        get { elevationData.isEmpty ? nil : try? JSONDecoder().decode(ElevationProfile.self, from: elevationData) }
        set {
            elevationData = newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data()
            elevationGain = newValue?.gain ?? 0
            elevationLoss = newValue?.loss ?? 0
        }
    }

    var hasElevation: Bool { !elevationData.isEmpty }

    /// Start und Ziel liegen nah beieinander (Rundkurs)
    var isLoop: Bool {
        guard let first = path.first, let last = path.last, path.count > 2 else { return false }
        return first.distance(to: last) < 50
    }
}

/// Geometrie auf einer Route: Länge, Abstand zur Route und Fortschritt.
enum RouteGeometry {
    static func length(_ path: [RouteCoordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Kürzester Abstand (Meter) eines Punkts zur Route und die zurückgelegte Strecke
    /// entlang der Route bis zum nächstgelegenen Punkt.
    /// Für kurze Abschnitte wird lokal eben gerechnet (ausreichend genau für Laufstrecken).
    /// Mit `range` werden nur Abschnitte in diesem Bereich (Meter entlang der Route) betrachtet,
    /// z. B. damit bei einem Rundkurs der Start nicht als Ziel erkannt wird.
    static func nearest(to point: RouteCoordinate, on path: [RouteCoordinate],
                        within range: ClosedRange<Double>? = nil)
        -> (distance: Double, alongRoute: Double)?
    {
        guard let first = path.first else { return nil }
        if path.count == 1 { return (point.distance(to: first), 0) }
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(point.latitude * .pi / 180)
        func xy(_ c: RouteCoordinate) -> (Double, Double) {
            ((c.longitude - point.longitude) * metersPerDegLon, (c.latitude - point.latitude) * metersPerDegLat)
        }
        var best = (distance: Double.infinity, alongRoute: 0.0)
        var covered = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let (ax, ay) = xy(a), (bx, by) = xy(b)
            let dx = bx - ax, dy = by - ay
            let segLength = (dx * dx + dy * dy).squareRoot()
            if let range, covered + segLength < range.lowerBound || covered > range.upperBound {
                covered += segLength
                continue
            }
            // Projektion des Punkts (Ursprung) auf den Abschnitt
            let t = segLength > 0 ? max(0, min(1, -(ax * dx + ay * dy) / (segLength * segLength))) : 0
            let px = ax + t * dx, py = ay + t * dy
            let d = (px * px + py * py).squareRoot()
            if d < best.distance { best = (d, covered + t * segLength) }
            covered += segLength
        }
        return best.distance.isFinite ? best : nil
    }
}
