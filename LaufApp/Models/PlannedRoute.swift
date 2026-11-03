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

extension PlannedRoute {
    /// Route aus einem gelaufenen Lauf: die GPS-Strecke (vereinfacht) als Verlauf, dazu Wegpunkte
    /// etwa alle 500 m, damit sich die Route später im Editor anpassen lässt.
    static func fromRun(_ run: Run, name: String) -> PlannedRoute? {
        let points = run.route.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        var path = RouteGeometry.simplified(points, tolerance: 3)
        guard path.count > 1, RouteGeometry.length(path) > 100 else { return nil }
        // Endet der Lauf nahe am Start, als Rundkurs schließen
        if let first = path.first, let last = path.last, first.distance(to: last) < 80, first.distance(to: last) > 1 {
            path.append(first)
        }
        var waypoints = [path[0]]
        var sinceLast = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            sinceLast += a.distance(to: b)
            if sinceLast >= 500 {
                waypoints.append(b)
                sinceLast = 0
            }
        }
        if let last = path.last, waypoints.last.map({ $0.distance(to: last) > 30 }) ?? true {
            waypoints.append(last)
        } else if let last = path.last {
            waypoints[waypoints.count - 1] = last
        }
        return PlannedRoute(name: name, waypoints: waypoints, path: path, followsPaths: true)
    }

    /// Vorschlag für den Namen einer Route aus einem Lauf, z. B. „Morgenlauf · 28. Okt.“
    static func defaultName(for run: Run) -> String {
        "\(run.title) · \(run.startDate.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// Geometrie auf einer Route: Länge, Abstand zur Route und Fortschritt.
enum RouteGeometry {
    /// Abzweigungen entlang der Route. Die Laufrichtung wird jeweils über 20 m vor und nach einem Punkt
    /// bestimmt; ändert sie sich um mindestens 35°, ist dort eine Abzweigung (die stärkste Stelle zählt).
    static func turns(_ path: [RouteCoordinate]) -> [RouteTurn] {
        let samples = ElevationService.resample(path, every: 5)
        let k = 4   // 4 × 5 m = 20 m
        guard samples.count > 2 * k + 1 else { return [] }
        func bearing(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Double {
            let dx = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
            let dy = b.latitude - a.latitude
            return atan2(dx, dy) * 180 / .pi   // 0 = Norden, 90 = Osten
        }
        var angles = [Double](repeating: 0, count: samples.count)
        for i in k..<(samples.count - k) {
            let incoming = bearing(samples[i - k].point, samples[i].point)
            let outgoing = bearing(samples[i].point, samples[i + k].point)
            var d = (outgoing - incoming).truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            angles[i] = d
        }
        let total = samples.last?.along ?? 0
        var result: [RouteTurn] = []
        var i = k
        while i < samples.count - k {
            guard abs(angles[i]) >= 35 else { i += 1; continue }
            // Zusammenhängenden Bereich gleicher Richtung suchen und die stärkste Stelle nehmen
            var best = i
            var j = i
            while j < samples.count - k, abs(angles[j]) >= 35, (angles[j] > 0) == (angles[i] > 0) {
                if abs(angles[j]) > abs(angles[best]) { best = j }
                j += 1
            }
            let along = samples[best].along
            // Gegenprobe über 40 m: Bei kleinen Schlenkern hebt sich die Richtungsänderung auf
            let wide = 8
            let lo = max(0, best - wide), hi = min(samples.count - 1, best + wide)
            var net = (bearing(samples[best].point, samples[hi].point) - bearing(samples[lo].point, samples[best].point))
                .truncatingRemainder(dividingBy: 360)
            if net > 180 { net -= 360 }
            if net < -180 { net += 360 }
            let consistent = abs(net) >= 30 && (net > 0) == (angles[best] > 0)
            if consistent, along > 15, total - along > 15, let direction = TurnDirection(angle: angles[best]) {
                // Dicht aufeinanderfolgende Knicke in dieselbe Richtung zusammenfassen
                if let last = result.last, along - last.along < 25,
                   (last.direction.instruction.contains("links")) == (direction.instruction.contains("links")) {
                    result[result.count - 1] = RouteTurn(along: along, direction: direction)
                } else {
                    result.append(RouteTurn(along: along, direction: direction))
                }
            }
            i = j + 1
        }
        return result
    }

    /// Weniger Punkte bei gleicher Form (Douglas-Peucker, Toleranz in Metern)
    static func simplified(_ path: [RouteCoordinate], tolerance: Double) -> [RouteCoordinate] {
        guard path.count > 2 else { return path }
        var keep = [Bool](repeating: false, count: path.count)
        keep[0] = true
        keep[path.count - 1] = true
        var stack = [(0, path.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let segment = [path[start], path[end]]
            var maxDistance = 0.0, index = start
            for i in (start + 1)..<end {
                let d = nearest(to: path[i], on: segment)?.distance ?? 0
                if d > maxDistance { maxDistance = d; index = i }
            }
            if maxDistance > tolerance {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return path.indices.filter { keep[$0] }.map { path[$0] }
    }

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
