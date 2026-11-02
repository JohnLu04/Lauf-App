import Foundation

/// Vorgeschlagener Rundkurs.
struct LoopSuggestion: Identifiable {
    let id = UUID()
    var waypoints: [RouteCoordinate]
    var path: [RouteCoordinate]
    var distance: Double
    /// z. B. ["Bürgerpark", "Wald"]
    var highlights: [String]

    /// Führt durch Grünflächen (sonst geometrische Runde)
    var isGreen = false
    var elevation: ElevationProfile?

    var title: String {
        highlights.isEmpty ? "Rundkurs" : highlights.prefix(2).joined(separator: " · ")
    }
}

/// Erzeugt Rundkurse in Wunschdistanz vom Startpunkt aus, bevorzugt durch Grünflächen.
///
/// Rundenformen:
/// - Dreieck Start → Grünfläche A → Grünfläche B → Start (Flächen weiter weg)
/// - Kreis durch eine Grünfläche (Flächen in der Nähe; Größe passend zur Wunschdistanz)
/// - Drachenform zu einer einzelnen Fläche
/// - Geometrischer Kreis (Viereck) in eine Richtung, falls nichts Grünes passt
///
/// Echte Wege sind länger als die Luftlinie. Der Umwegfaktor startet bei 1,3 und lernt aus jeder
/// berechneten Runde dazu; Kreisrunden werden damit neu gebaut, bis die Länge passt (±15 %).
enum LoopGenerator {
    static let initialDetour = 1.3
    static let tolerance = 0.15
    /// Umfang eines Vierecks auf einem Kreis mit Radius 1
    private static let squarePerimeter = 4 * 2.0.squareRoot()

    /// Bauart einer Runde, damit sie mit besserem Umwegfaktor neu gebaut werden kann
    enum Shape {
        /// Feste Punkte (Grünflächen), nicht skalierbar
        case fixed
        /// Geometrische Runde in Richtung `bearing`
        case circle(bearing: Double)
        /// Kreis durch eine Grünfläche, `side` = ±1 (links/rechts der Verbindungslinie)
        case through(point: RouteCoordinate, side: Double)
    }

    struct Plan {
        var waypoints: [RouteCoordinate]
        var spaces: [GreenSpace]
        /// Länge der Runde in Luftlinie (Meter)
        var straightLength: Double
        var shape: Shape
        var score: Double

        func estimate(detour: Double) -> Double { straightLength * detour }

        var isScalable: Bool { if case .fixed = shape { false } else { true } }
        var isGeometric: Bool { if case .circle = shape { true } else { false } }

        /// Hauptrichtung der Runde vom Start aus (für Abwechslung zwischen den Vorschlägen)
        func bearing(from start: RouteCoordinate) -> Double {
            if case let .circle(bearing) = shape { return bearing }
            let lat = waypoints.map(\.latitude).reduce(0, +) / Double(waypoints.count)
            let lon = waypoints.map(\.longitude).reduce(0, +) / Double(waypoints.count)
            return Geo.bearing(from: start, to: RouteCoordinate(latitude: lat, longitude: lon))
        }
    }

    // MARK: - Planung (ohne Netz)

    /// Kandidaten, beste zuerst: höchstens `maxGreen` Grünflächen-Runden in unterschiedliche
    /// Richtungen, aufgefüllt mit geometrischen Runden.
    static func plans(start: RouteCoordinate, target: Double, spaces: [GreenSpace],
                      detour: Double = initialDetour, maxGreen: Int = 3, total: Int = 6,
                      geometricSpacing: Double = 90) -> [Plan] {
        let radius = target / (squarePerimeter * detour)
        // Erreichbare Flächen mit ihrem Zielpunkt
        let list = Array(spaces
            .map { (space: $0, point: $0.waypoint(from: start)) }
            .filter { let d = start.distance(to: $0.point); return d > 120 && d < target * 0.45 }
            .sorted { $0.space.score > $1.space.score }
            .prefix(30))

        var green: [Plan] = []
        for i in list.indices {
            let a = list[i]
            for j in list.indices where j > i {
                let b = list[j]
                let angle = angleBetween(Geo.bearing(from: start, to: a.point), Geo.bearing(from: start, to: b.point))
                // Zu schmale Dreiecke laufen doppelt, gegenüberliegende Punkte führen über den Start
                guard angle > 25, angle < 150 else { continue }
                // Reihenfolge im Uhrzeigersinn, damit sich die Runde nicht kreuzt
                let (p, q) = clockwise(start: start, a.point, b.point)
                let straight = start.distance(to: p) + p.distance(to: q) + q.distance(to: start)
                let deviation = abs(straight * detour - target) / target
                guard deviation < 0.25 else { continue }
                green.append(Plan(waypoints: [p, q], spaces: p == a.point ? [a.space, b.space] : [b.space, a.space],
                                  straightLength: straight, shape: .fixed,
                                  score: a.space.score + b.space.score - 4 * deviation))
            }
            // Kreis durch eine nahe Fläche, passend zur Wunschdistanz (beide Seiten)
            for side in [1.0, -1.0] {
                if let plan = throughPlan(start: start, point: a.point, side: side, radius: radius) {
                    var plan = plan
                    plan.spaces = [a.space]
                    plan.score = a.space.score - 0.2
                    green.append(plan)
                }
            }
            // Drachenform zu einer weiter entfernten Fläche
            let d = start.distance(to: a.point), bearing = Geo.bearing(from: start, to: a.point)
            let left = Geo.destination(from: start, bearing: bearing - 45, distance: d * 0.65)
            let right = Geo.destination(from: start, bearing: bearing + 45, distance: d * 0.65)
            let straight = start.distance(to: left) + left.distance(to: a.point) + a.point.distance(to: right)
                + right.distance(to: start)
            let deviation = abs(straight * detour - target) / target
            if deviation < 0.25 {
                green.append(Plan(waypoints: [left, a.point, right], spaces: [a.space], straightLength: straight,
                                  shape: .fixed, score: a.space.score - 0.5 - 4 * deviation))
            }
        }

        // Abwechslung: keine Fläche doppelt, Richtungen mindestens 50° auseinander
        var result: [Plan] = []
        for plan in green.sorted(by: { $0.score > $1.score }) where result.count < maxGreen {
            let usedSpaces = Set(result.flatMap(\.spaces))
            guard plan.spaces.allSatisfy({ !usedSpaces.contains($0) }) else { continue }
            let b = plan.bearing(from: start)
            guard result.allSatisfy({ angleBetween($0.bearing(from: start), b) > 50 }) else { continue }
            result.append(plan)
        }

        // Geometrische Runden in die Richtungen, die noch frei sind
        let used = result.map { $0.bearing(from: start) }
        let directions = stride(from: 0.0, to: 360, by: 30)
            .sorted { minAngle($0, used) > minAngle($1, used) }
        var geometricBearings: [Double] = []
        for b in directions where result.count + geometricBearings.count < total {
            if geometricBearings.allSatisfy({ angleBetween($0, b) >= geometricSpacing }) { geometricBearings.append(b) }
        }
        for b in geometricBearings {
            result.append(circlePlan(start: start, bearing: b, radius: radius))
        }
        return result
    }

    /// Viereck auf einem Kreis, der durch den Start geht und in Richtung `bearing` liegt.
    static func circlePlan(start: RouteCoordinate, bearing: Double, radius: Double) -> Plan {
        let center = Geo.destination(from: start, bearing: bearing, distance: radius)
        let points = [90.0, 180, 270].map { Geo.destination(from: center, bearing: bearing + 180 + $0, distance: radius) }
        return Plan(waypoints: points, spaces: [], straightLength: squarePerimeter * radius,
                    shape: .circle(bearing: bearing), score: 0)
    }

    /// Viereck auf einem Kreis durch Start und `point`. nil, wenn der Punkt für den Kreis zu weit weg ist.
    static func throughPlan(start: RouteCoordinate, point: RouteCoordinate, side: Double, radius: Double) -> Plan? {
        let d = start.distance(to: point)
        guard d > 50, d < 1.9 * radius else { return nil }
        // Lokale ebene Koordinaten in Metern, Ursprung = Start
        let mLon = 111_320 * cos(start.latitude * .pi / 180)
        let px = (point.longitude - start.longitude) * mLon, py = (point.latitude - start.latitude) * 111_320
        let h = (radius * radius - d * d / 4).squareRoot()
        let cx = px / 2 - py / d * h * side, cy = py / 2 + px / d * h * side
        func coordinate(angle: Double) -> RouteCoordinate {
            RouteCoordinate(latitude: start.latitude + (cy + radius * sin(angle)) / 111_320,
                            longitude: start.longitude + (cx + radius * cos(angle)) / mLon)
        }
        let angleStart = atan2(-cy, -cx), anglePoint = atan2(py - cy, px - cx)
        // Drei weitere Ecken im Abstand von 90°, die nächstgelegene wird durch die Grünfläche ersetzt
        let angles = [1.0, 2, 3].map { angleStart + $0 * .pi / 2 }
        let replace = angles.indices.min {
            abs(remainder(angles[$0] - anglePoint, 2 * .pi)) < abs(remainder(angles[$1] - anglePoint, 2 * .pi))
        }!
        let waypoints = angles.indices.map { $0 == replace ? point : coordinate(angle: angles[$0]) }
        let all = [start] + waypoints + [start]
        let straight = zip(all, all.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        return Plan(waypoints: waypoints, spaces: [], straightLength: straight,
                    shape: .through(point: point, side: side), score: 0)
    }

    /// Baut eine skalierbare Runde mit neuem Umwegfaktor passend zur Wunschdistanz neu.
    static func rebuild(_ plan: Plan, start: RouteCoordinate, target: Double, detour: Double) -> Plan {
        // Der Radius wird so gewählt, dass Luftlinie × Umwegfaktor ≈ Wunschdistanz
        func scaled(_ make: (Double) -> Plan?) -> Plan? {
            var radius = target / (squarePerimeter * detour)
            guard var result = make(radius) else { return nil }
            radius *= target / (result.straightLength * detour)   // Feinabgleich (unregelmäßige Vierecke)
            if let refined = make(radius) { result = refined }
            return result
        }
        switch plan.shape {
        case .fixed:
            return plan
        case let .circle(bearing):
            return scaled { circlePlan(start: start, bearing: bearing, radius: $0) } ?? plan
        case let .through(point, side):
            guard var rebuilt = scaled({ throughPlan(start: start, point: point, side: side, radius: $0) })
            else { return plan }
            rebuilt.spaces = plan.spaces
            rebuilt.score = plan.score
            return rebuilt
        }
    }

    // MARK: - Wegsuche

    /// Berechnet bis zu `count` Rundkurse entlang der Wege. `progress` meldet den Fortschritt.
    static func suggestions(start: RouteCoordinate, target: Double, spaces: [GreenSpace], count: Int = 3,
                            avoidClimbs: Bool = false,
                            progress: @MainActor (String) -> Void) async -> [LoopSuggestion] {
        var accepted: [LoopSuggestion] = []
        var acceptedBearings: [Double] = []
        var detour = initialDetour
        // Für flache Runden mehr Richtungen ausprobieren
        var candidates = avoidClimbs
            ? plans(start: start, target: target, spaces: spaces, maxGreen: 4, total: 10, geometricSpacing: 60)
            : plans(start: start, target: target, spaces: spaces)
        if avoidClimbs {
            await progress("Höhenlage wird geprüft …")
            candidates = await sortedByClimb(candidates, start: start)
        }
        GreenSpaceFinder.log.info("\(spaces.count) Grünflächen, \(candidates.filter { !$0.isGeometric }.count) grüne Kandidaten")
        for plan in candidates {
            guard accepted.count < count, !Task.isCancelled else { break }
            let bearing = plan.bearing(from: start)
            if acceptedBearings.contains(where: { angleBetween($0, bearing) < 45 }) { continue }
            // Feste Runden, die mit dem gelernten Umwegfaktor sicher nicht passen, gar nicht erst berechnen
            if !plan.isScalable, abs(plan.estimate(detour: detour) - target) / target > tolerance + 0.1 { continue }
            await progress("Runde \(accepted.count + 1) von \(count) wird berechnet …")

            for attempt in 0..<2 {
                let current = rebuild(plan, start: start, target: target, detour: detour)
                guard let routed = await route(current, start: start) else {
                    GreenSpaceFinder.log.info("Runde verworfen (kein Weg gefunden): \(plan.spaces.map(\.label), privacy: .public)")
                    break
                }
                // Umwegfaktor aus der echten Länge lernen (geglättet und begrenzt)
                let observed = routed.distance / max(1, current.straightLength)
                // Kürzer als die Luftlinie geht nur, wenn Stichwege herausgeschnitten wurden – daraus nicht lernen
                if observed >= 1.05 { detour = min(2.2, max(1.1, (detour + observed) / 2)) }
                let deviation = abs(routed.distance - target) / target
                GreenSpaceFinder.log.info("Runde \(plan.spaces.map(\.label), privacy: .public): geschätzt \(Int(current.estimate(detour: detour))) m, echt \(Int(routed.distance)) m, Umwegfaktor jetzt \(detour)")
                if deviation <= tolerance {
                    accepted.append(routed)
                    acceptedBearings.append(bearing)
                    break
                }
                guard plan.isScalable else { break }
            }
        }
        // Höhenprofile der fertigen Runden
        if !accepted.isEmpty {
            await progress("Höhenmeter werden berechnet …")
            let paths = accepted.map(\.path)
            let profiles = await withTaskGroup(of: (Int, ElevationProfile?).self) { group in
                for (i, path) in paths.enumerated() { group.addTask { (i, await ElevationService.profile(for: path)) } }
                var result = [ElevationProfile?](repeating: nil, count: paths.count)
                for await (i, profile) in group { result[i] = profile }
                return result
            }
            for i in accepted.indices { accepted[i].elevation = profiles[i] }
        }
        if avoidClimbs {
            // Flachste zuerst (Runden ohne Höhendaten ans Ende)
            return accepted.sorted { ($0.elevation?.gain ?? .infinity) < ($1.elevation?.gain ?? .infinity) }
        }
        // Runden durch Grünflächen zuerst, dann nach Passgenauigkeit
        return accepted.sorted {
            if $0.isGreen != $1.isGreen { return $0.isGreen }
            return abs($0.distance - target) < abs($1.distance - target)
        }
    }

    /// Ordnet die Kandidaten nach geschätztem Anstieg zwischen ihren Wegpunkten (eine Anfrage für alle).
    /// Runden durch Grünflächen bekommen einen kleinen Bonus (10 m), damit sie bei ähnlicher Höhe vorne bleiben.
    static func sortedByClimb(_ candidates: [Plan], start: RouteCoordinate) async -> [Plan] {
        let points = [start] + candidates.flatMap(\.waypoints)
        guard let heights = try? await ElevationService.elevations(points), heights.count == points.count
        else { return candidates }
        var index = 1
        let climbs: [Double] = candidates.map { plan in
            let own = heights[index..<index + plan.waypoints.count]
            index += plan.waypoints.count
            let sequence = [heights[0]] + own + [heights[0]]
            return zip(sequence, sequence.dropFirst()).reduce(0) { $0 + max(0, $1.1 - $1.0) }
        }
        GreenSpaceFinder.log.info("Geschätzte Anstiege der Kandidaten: \(climbs.map { Int($0) }, privacy: .public)")
        return zip(candidates, climbs)
            .sorted { ($0.1 - ($0.0.spaces.isEmpty ? 0 : 10)) < ($1.1 - ($1.0.spaces.isEmpty ? 0 : 10)) }
            .map(\.0)
    }

    private static func route(_ plan: Plan, start: RouteCoordinate) async -> LoopSuggestion? {
        let points = [start] + plan.waypoints + [start]
        let segments = await withTaskGroup(of: (Int, RoutePlanner.Segment).self) { group in
            for (i, (a, b)) in zip(points, points.dropFirst()).enumerated() {
                group.addTask { (i, await RoutePlanner.segment(from: a, to: b, followPaths: true)) }
            }
            var result = [RoutePlanner.Segment?](repeating: nil, count: points.count - 1)
            for await (i, segment) in group { result[i] = segment }
            return result.compactMap { $0 }
        }
        // Längere Abschnitte ohne gefundenen Weg (Luftlinie) sind kein brauchbarer Vorschlag
        guard segments.count == points.count - 1,
              !segments.contains(where: { !$0.followsPaths && RouteGeometry.length($0.coordinates) > 150 })
        else { return nil }
        let path = removeSpurs(segments.reduce([start]) { $0 + $1.coordinates.dropFirst() })
        // Keine „Lollis“: Runden, die zu großen Teilen auf demselben Weg zurückführen, verwerfen
        let retraced = retracedShare(path)
        guard retraced <= 0.2 else {
            GreenSpaceFinder.log.info("Runde verworfen (\(Int(retraced * 100)) % doppelt gelaufen): \(plan.spaces.map(\.label), privacy: .public)")
            return nil
        }
        var highlights: [String] = []
        for space in plan.spaces where !highlights.contains(space.label) { highlights.append(space.label) }
        if plan.isGeometric { highlights = ["Richtung \(Geo.compassName(plan.bearing(from: start)))"] }
        return LoopSuggestion(waypoints: plan.waypoints, path: path, distance: RouteGeometry.length(path),
                              highlights: highlights, isGreen: !plan.spaces.isEmpty)
    }

    // MARK: - Hilfen

    /// Anteil der Strecke (0…1), der auf einem schon gelaufenen Abschnitt verläuft (Hin und zurück).
    static func retracedShare(_ path: [RouteCoordinate], sampleEvery: Double = 25, tolerance: Double = 15) -> Double {
        // Gleichmäßige Stützpunkte entlang der Strecke
        var samples: [(point: RouteCoordinate, along: Double)] = []
        var along = 0.0, next = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let d = a.distance(to: b)
            while next <= along + d, d > 0 {
                let t = (next - along) / d
                samples.append((RouteCoordinate(latitude: a.latitude + t * (b.latitude - a.latitude),
                                                longitude: a.longitude + t * (b.longitude - a.longitude)), next))
                next += sampleEvery
            }
            along += d
        }
        guard samples.count > 4 else { return 0 }
        // Ein Stützpunkt gilt als doppelt, wenn ein deutlich früherer (> 200 m davor) ganz nah liegt;
        // die letzten 200 m vor dem Ziel zählen nicht (Rückkehr zum Start ist gewollt).
        var retraced = 0
        for k in samples.indices where samples[k].along < along - 200 {
            let p = samples[k]
            if samples[..<k].contains(where: { p.along - $0.along > 200 && $0.point.distance(to: p.point) < tolerance }) {
                retraced += 1
            }
        }
        return Double(retraced) / Double(samples.count)
    }

    /// Entfernt Stichwege: Abschnitte, die zu einem Wegpunkt hin- und auf demselben Weg zurückführen
    /// (entstehen, wenn ein Wegpunkt abseits eines Durchgangswegs liegt). Erkannt wird das, wenn der
    /// Weg nach höchstens `maxSpur` Metern wieder an einen Punkt zurückkommt, an dem er schon war.
    static func removeSpurs(_ path: [RouteCoordinate], tolerance: Double = 12, maxSpur: Double = 800) -> [RouteCoordinate] {
        guard path.count > 3 else { return path }
        let total = RouteGeometry.length(path)
        let limit = min(maxSpur, total * 0.2)
        var result: [RouteCoordinate] = []
        var i = 0
        while i < path.count {
            result.append(path[i])
            // Weiteste Rückkehr zu diesem Punkt innerhalb der Grenze suchen
            var covered = 0.0, jump: Int?
            var j = i + 1
            while j < path.count {
                covered += path[j - 1].distance(to: path[j])
                if covered > limit * 2 { break }
                if covered > 2 * tolerance, path[j].distance(to: path[i]) < tolerance { jump = j }
                j += 1
            }
            // Start und Ziel der Runde nicht wegschneiden
            if let jump, !(i == 0 && jump == path.count - 1) {
                i = jump + 1
            } else {
                i += 1
            }
        }
        if let last = path.last, result.last != last { result.append(last) }
        return result
    }

    static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360))
        return min(d, 360 - d)
    }

    private static func minAngle(_ b: Double, _ others: [Double]) -> Double {
        others.map { angleBetween($0, b) }.min() ?? 180
    }

    private static func clockwise(start: RouteCoordinate, _ a: RouteCoordinate, _ b: RouteCoordinate)
        -> (RouteCoordinate, RouteCoordinate)
    {
        let ba = Geo.bearing(from: start, to: a), bb = Geo.bearing(from: start, to: b)
        let diff = (bb - ba + 360).truncatingRemainder(dividingBy: 360)
        return diff < 180 ? (a, b) : (b, a)
    }
}

extension Geo {
    /// Richtung in Grad (0 = Norden, 90 = Osten)
    static func bearing(from a: RouteCoordinate, to b: RouteCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Punkt in `distance` Metern Entfernung in Richtung `bearing`
    static func destination(from start: RouteCoordinate, bearing: Double, distance: Double) -> RouteCoordinate {
        let r = 6_371_000.0, delta = distance / r, theta = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180, lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(delta) * cos(lat1), cos(delta) - sin(lat1) * sin(lat2))
        return RouteCoordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    static func compassName(_ bearing: Double) -> String {
        let names = ["Norden", "Nordosten", "Osten", "Südosten", "Süden", "Südwesten", "Westen", "Nordwesten"]
        return names[Int(((bearing + 22.5) / 45).rounded(.down)) % 8]
    }
}
