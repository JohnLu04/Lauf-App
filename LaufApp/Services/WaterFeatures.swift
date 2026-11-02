import Foundation

/// Fluss oder Kanal als Mittellinie (aus OpenStreetMap `waterway=river|canal`).
struct Waterway: Codable, Hashable {
    var name: String?
    var line: [RouteCoordinate]
    /// Ungefähre Breite in Metern (aus `width`, sonst geschätzt)
    var width: Double

    var length: Double { RouteGeometry.length(line) }
    var label: String { name ?? "Fluss" }

    /// Abstand der Uferwege von der Mittellinie
    var bankOffset: Double { width / 2 + 20 }

    /// Punkt auf der Mittellinie nach `along` Metern und die Flussrichtung dort (Grad).
    func position(at along: Double) -> (point: RouteCoordinate, bearing: Double)? {
        guard line.count > 1 else { return nil }
        var covered = 0.0
        for (a, b) in zip(line, line.dropFirst()) {
            let d = a.distance(to: b)
            if covered + d >= along, d > 0 {
                let t = (along - covered) / d
                let p = RouteCoordinate(latitude: a.latitude + t * (b.latitude - a.latitude),
                                        longitude: a.longitude + t * (b.longitude - a.longitude))
                return (p, Geo.bearing(from: a, to: b))
            }
            covered += d
        }
        guard let last = line.last, let prev = line.dropLast().last else { return nil }
        return (last, Geo.bearing(from: prev, to: last))
    }

    /// Uferpunkt nach `along` Metern; `side` +1 = rechts, -1 = links (in Fließrichtung der Linie).
    func bankPoint(at along: Double, side: Double) -> RouteCoordinate? {
        guard let pos = position(at: along) else { return nil }
        return Geo.destination(from: pos.point, bearing: pos.bearing + 90 * side, distance: bankOffset)
    }

    /// Seite (+1/-1) und Lage eines Punkts relativ zur Mittellinie.
    func locate(_ point: RouteCoordinate) -> (distance: Double, along: Double, side: Double)? {
        guard let nearest = RouteGeometry.nearest(to: point, on: line),
              let pos = position(at: nearest.alongRoute) else { return nil }
        let toPoint = Geo.bearing(from: pos.point, to: point)
        let relative = (toPoint - pos.bearing + 360).truncatingRemainder(dividingBy: 360)
        return (nearest.distance, nearest.alongRoute, relative < 180 ? 1 : -1)
    }

    // MARK: - Aus OpenStreetMap

    static func width(tags: [String: String]) -> Double {
        if let raw = tags["width"]?.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: CharacterSet(charactersIn: " m")),
           let value = Double(raw), value > 1, value < 1000 { return value }
        return tags["waterway"] == "canal" ? 20 : 40
    }

    /// Fügt Abschnitte zu durchgehenden Linien zusammen (Enden innerhalb von 30 m). Verbunden werden
    /// Abschnitte gleichen Namens sowie namenlose mit allen Nachbarn – in OpenStreetMap fehlt der Name
    /// manchmal an einzelnen Abschnitten eines Flusses.
    static func merge(_ parts: [Waterway]) -> [Waterway] {
        var result: [Waterway] = []
        var pool = parts.filter { $0.line.count > 1 }.sorted { $0.length < $1.length }
        while var current = pool.popLast() {
            var extended = true
            while extended {
                extended = false
                for (i, other) in pool.enumerated() where current.name == nil || other.name == nil || current.name == other.name {
                    let (a0, a1) = (current.line.first!, current.line.last!)
                    let (b0, b1) = (other.line.first!, other.line.last!)
                    var joined: [RouteCoordinate]?
                    if a1.distance(to: b0) < 30 { joined = current.line + other.line.dropFirst() }
                    else if a1.distance(to: b1) < 30 { joined = current.line + other.line.reversed().dropFirst() }
                    else if a0.distance(to: b1) < 30 { joined = other.line + current.line.dropFirst() }
                    else if a0.distance(to: b0) < 30 { joined = other.line.reversed() + current.line.dropFirst() }
                    if let joined {
                        current.line = joined
                        current.name = current.name ?? other.name
                        current.width = max(current.width, other.width)
                        pool.remove(at: i)
                        extended = true
                        break
                    }
                }
            }
            result.append(current)
        }
        // Kurze Stücke (z. B. Seitenarme) bringen für Uferrunden nichts
        return result.filter { $0.length > 500 }.sorted { $0.length > $1.length }
    }
}

/// Gewässer in der Umgebung: Flüsse (Linien) und Seen (Flächen aus den Grünflächen).
struct WaterFeatures {
    var rivers: [Waterway] = []
    var lakes: [GreenSpace] = []

    var isEmpty: Bool { rivers.isEmpty && lakes.isEmpty }

    /// Verschiebt einen Punkt, der im Wasser liegt, ans nächste Ufer (20 m vom Wasser entfernt).
    /// Geplante Wegpunkte im Wasser führen sonst zu Umwegen über die nächste Brücke.
    func movedOutOfWater(_ point: RouteCoordinate) -> RouteCoordinate {
        for river in rivers {
            guard let loc = river.locate(point), loc.distance < river.width / 2 + 10,
                  let pos = river.position(at: loc.along) else { continue }
            return Geo.destination(from: pos.point, bearing: pos.bearing + 90 * loc.side, distance: river.bankOffset)
        }
        for lake in lakes where lake.contains(point, inset: 0.15) {
            // Zur nächsten Kante des Sees und 20 m darüber hinaus
            let toWest = (point.longitude - lake.minLon), toEast = (lake.maxLon - point.longitude)
            let toSouth = (point.latitude - lake.minLat), toNorth = (lake.maxLat - point.latitude)
            let mLon = 111_320 * cos(point.latitude * .pi / 180)
            let options: [(Double, RouteCoordinate)] = [
                (toWest * mLon, RouteCoordinate(latitude: point.latitude, longitude: lake.minLon - 20 / mLon)),
                (toEast * mLon, RouteCoordinate(latitude: point.latitude, longitude: lake.maxLon + 20 / mLon)),
                (toSouth * 111_320, RouteCoordinate(latitude: lake.minLat - 20 / 111_320, longitude: point.longitude)),
                (toNorth * 111_320, RouteCoordinate(latitude: lake.maxLat + 20 / 111_320, longitude: point.longitude)),
            ]
            return options.min { $0.0 < $1.0 }!.1
        }
        return point
    }

    /// Anteil der Strecke (0…1), der höchstens 150 m von einem Fluss oder See entfernt verläuft.
    func shareNearWater(_ path: [RouteCoordinate]) -> Double {
        let samples = ElevationService.resample(path, every: 100).map(\.point)
        guard !samples.isEmpty, !isEmpty else { return 0 }
        let near = samples.filter { p in
            rivers.contains { ($0.locate(p)?.distance ?? .infinity) < $0.width / 2 + 150 }
                || lakes.contains { $0.contains(p, inset: -0.002) }
        }
        return Double(near.count) / Double(samples.count)
    }

    /// Name des nächstgelegenen Gewässers an der Strecke (für die Anzeige)
    func nearestName(to path: [RouteCoordinate]) -> String? {
        let samples = ElevationService.resample(path, every: 200).map(\.point)
        let river = rivers.min { a, b in
            let da = samples.map { a.locate($0)?.distance ?? .infinity }.min() ?? .infinity
            let db = samples.map { b.locate($0)?.distance ?? .infinity }.min() ?? .infinity
            return da < db
        }
        return river?.name
    }
}

extension GreenSpace {
    /// Liegt der Punkt innerhalb des Rechtecks? `inset` > 0 verkleinert, < 0 vergrößert (Anteil bzw. Grad).
    func contains(_ point: RouteCoordinate, inset: Double) -> Bool {
        let dLat = inset > 0 ? (maxLat - minLat) * inset : inset
        let dLon = inset > 0 ? (maxLon - minLon) * inset : inset
        return point.latitude > minLat + dLat && point.latitude < maxLat - dLat
            && point.longitude > minLon + dLon && point.longitude < maxLon - dLon
    }
}
