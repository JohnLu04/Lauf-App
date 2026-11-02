import Foundation
import MapKit
import os

/// Grünfläche oder anderer schöner Ort zum Laufen (Park, Wald, Laufbahn, See).
struct GreenSpace: Codable, Hashable {
    enum Kind: String, Codable {
        case park, forest, nature, track, water

        var name: String {
            switch self {
            case .park: "Park"
            case .forest: "Wald"
            case .nature: "Naturschutzgebiet"
            case .track: "Laufbahn"
            case .water: "See"
            }
        }
    }

    var name: String?
    var kind: Kind
    var minLat: Double
    var minLon: Double
    var maxLat: Double
    var maxLon: Double

    var center: RouteCoordinate { RouteCoordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2) }

    /// Ungefähre Fläche (m²) aus dem umgebenden Rechteck
    var area: Double {
        let h = (maxLat - minLat) * 111_320
        let w = (maxLon - minLon) * 111_320 * cos(minLat * .pi / 180)
        return max(1, w * h * 0.6)
    }

    var label: String { name ?? kind.name }

    /// Orte, die zwar als Park gelten, sich aber nicht als Ziel einer Laufrunde eignen
    var isUnsuitable: Bool {
        guard let name = name?.lowercased() else { return false }
        return ["spielplatz", "bolzplatz", "friedhof", "kleingarten", "schrebergarten", "kräuter", "beet", "hundewiese"]
            .contains { name.contains($0) }
    }

    /// Wie lohnend der Ort für eine Laufrunde ist: größer ist besser (logarithmisch, gedeckelt).
    var score: Double {
        let size = min(5.5, max(3, log10(area)))   // 1.000 m² … ~300 ha
        let bonus: Double = switch kind {
        case .track: 0.8
        case .nature, .forest: 0.5
        case .water: 0.4
        case .park: 0.3
        }
        return size - 3 + bonus + (name != nil ? 0.3 : 0)
    }

    /// Punkt, den die Route ansteuert: bei großen Flächen der Rand Richtung Start (etwas nach innen),
    /// damit die Runde nicht quer durch einen ganzen Wald geplant wird.
    func waypoint(from start: RouteCoordinate) -> RouteCoordinate {
        let c = center
        let diagonal = RouteCoordinate(latitude: minLat, longitude: minLon)
            .distance(to: RouteCoordinate(latitude: maxLat, longitude: maxLon))
        guard diagonal > 500 else { return c }
        let edge = RouteCoordinate(latitude: min(max(start.latitude, minLat), maxLat),
                                   longitude: min(max(start.longitude, minLon), maxLon))
        return RouteCoordinate(latitude: edge.latitude + (c.latitude - edge.latitude) * 0.25,
                               longitude: edge.longitude + (c.longitude - edge.longitude) * 0.25)
    }
}

/// Sucht Grünflächen in der Umgebung.
///
/// Die öffentlichen OpenStreetMap-Server (Overpass) sind oft überlastet und antworten teils erst nach
/// Minuten. Deshalb: alle Server gleichzeitig fragen (die erste Antwort gewinnt), höchstens `osmWait`
/// Sekunden warten und sonst Parks aus Apple Karten verwenden. Die OpenStreetMap-Abfrage läuft im
/// Hintergrund weiter und wird pro Gegend (~1 km) 14 Tage zwischengespeichert, sodass beim nächsten
/// Mal die genaueren Daten sofort da sind.
enum GreenSpaceFinder {
    enum Source { case openStreetMap, appleMaps, none }

    /// Ergebnis einer Abfrage: Grünflächen und Flüsse (Flüsse gibt es nur von OpenStreetMap).
    struct Result: Codable {
        var spaces: [GreenSpace]
        var rivers: [Waterway]

        var water: WaterFeatures { WaterFeatures(rivers: rivers, lakes: spaces.filter { $0.kind == .water }) }
    }

    static let log = Logger(subsystem: "de.josc.LaufApp", category: "Routes")

    static let overpassServers = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ].compactMap(URL.init(string:))

    static func find(near center: RouteCoordinate, radius: Double,
                     osmWait: TimeInterval = 12) async -> (result: Result, source: Source) {
        let radius = min(8000, max(1000, radius))
        if let cached = loadCache(center: center, radius: radius) {
            log.info("Aus Zwischenspeicher: \(cached.spaces.count) Grünflächen, \(cached.rivers.count) Flüsse")
            return (cached, .openStreetMap)
        }
        async let apple = fetchApplePOIs(center: center, radius: radius)
        // Läuft unabhängig weiter, auch wenn wir nicht auf das Ergebnis warten
        let osmTask = Task.detached { () -> Result? in
            guard let result = await fetchOverpassFromAnyServer(center: center, radius: radius),
                  !result.spaces.isEmpty || !result.rivers.isEmpty
            else { return nil }
            saveCache(result, center: center, radius: radius)
            return result
        }
        if let osm = await waitForValue(of: osmTask, seconds: osmWait) {
            log.info("Von OpenStreetMap: \(osm.spaces.count) Grünflächen, \(osm.rivers.count) Flüsse")
            return (osm, .openStreetMap)
        }
        let appleSpaces = await apple
        log.info("OpenStreetMap zu langsam, Parks von Apple Karten: \(appleSpaces.count)")
        return (Result(spaces: appleSpaces, rivers: []), appleSpaces.isEmpty ? .none : .appleMaps)
    }

    /// Ergebnis eines Tasks, falls er innerhalb der Frist fertig wird (der Task läuft sonst weiter).
    /// Bewusst ohne Task-Gruppe: Eine Gruppe wartet beim Beenden auf alle Kinder, auch auf das Warten
    /// auf `task.value`, das sich nicht abbrechen lässt – die Frist hätte dann keine Wirkung.
    private static func waitForValue<T: Sendable>(of task: Task<T?, Never>, seconds: TimeInterval) async -> T? {
        await withCheckedContinuation { continuation in
            let once = OnceFlag()
            Task {
                let value = await task.value
                if once.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    /// Fragt alle Overpass-Server gleichzeitig; die erste brauchbare Antwort gewinnt.
    static func fetchOverpassFromAnyServer(center: RouteCoordinate, radius: Double) async -> Result? {
        await withTaskGroup(of: Result?.self) { group in
            for server in overpassServers {
                group.addTask { try? await fetchOverpass(server: server, center: center, radius: radius) }
            }
            for await result in group {
                if let result, !result.spaces.isEmpty || !result.rivers.isEmpty {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    // MARK: - OpenStreetMap

    static func overpassQuery(center: RouteCoordinate, radius: Double) -> String {
        let around = "around:\(Int(radius)),\(center.latitude),\(center.longitude)"
        return """
        [out:json][timeout:25];
        (nwr["leisure"~"^(park|nature_reserve|track)$"](\(around));
         nwr["landuse"="forest"](\(around));
         nwr["natural"~"^(wood|water)$"](\(around)););
        out tags bb qt 400;
        way["waterway"~"^(river|canal)$"](\(around));
        out tags geom qt 80;
        """
    }

    private struct OverpassResponse: Decodable {
        struct Element: Decodable {
            struct Bounds: Decodable { let minlat, minlon, maxlat, maxlon: Double }
            struct Point: Decodable { let lat, lon: Double }
            let bounds: Bounds?
            let tags: [String: String]?
            let geometry: [Point]?
        }
        let elements: [Element]
    }

    static func fetchOverpass(server: URL, center: RouteCoordinate, radius: Double) async throws -> Result {
        var request = URLRequest(url: server, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("LaufApp (github.com/JohnLu04/Lauf-App)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "data", value: overpassQuery(center: center, radius: radius))]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return parseOverpass(data)
    }

    static func parseOverpass(_ data: Data) -> Result {
        guard let response = try? JSONDecoder().decode(OverpassResponse.self, from: data) else {
            return Result(spaces: [], rivers: [])
        }
        let riverParts: [Waterway] = response.elements.compactMap { element in
            guard let tags = element.tags, tags["waterway"] != nil, let geometry = element.geometry else { return nil }
            return Waterway(name: tags["name"], line: geometry.map { RouteCoordinate(latitude: $0.lat, longitude: $0.lon) },
                            width: Waterway.width(tags: tags))
        }
        let spaces: [GreenSpace] = response.elements.compactMap { element in
            guard let b = element.bounds, let tags = element.tags, tags["waterway"] == nil else { return nil }
            let kind: GreenSpace.Kind
            switch (tags["leisure"], tags["landuse"], tags["natural"]) {
            case ("track", _, _):
                // Nur Lauf-/Leichtathletikbahnen, keine Pferde- oder Kartbahnen
                if let sport = tags["sport"], !sport.contains("running") && !sport.contains("athletics") { return nil }
                kind = .track
            case ("park", _, _), ("garden", _, _): kind = .park
            case ("nature_reserve", _, _): kind = .nature
            case (_, "forest", _), (_, _, "wood"): kind = .forest
            case (_, _, "water"):
                guard ["lake", "pond", "reservoir", nil].contains(tags["water"]) else { return nil }
                kind = .water
            default: return nil
            }
            let space = GreenSpace(name: tags["name"], kind: kind,
                                   minLat: b.minlat, minLon: b.minlon, maxLat: b.maxlat, maxLon: b.maxlon)
            // Kleine Flächen bringen für eine Laufrunde nichts; bei Laufbahnen nur ganze Bahnen, keine Sprintgeraden
            return space.area >= (kind == .track ? 5000 : 8000) && !space.isUnsuitable ? space : nil
        }
        return Result(spaces: spaces, rivers: Waterway.merge(riverParts))
    }

    // MARK: - Apple Karten (Ersatz)

    static func fetchApplePOIs(center: RouteCoordinate, radius: Double) async -> [GreenSpace] {
        let request = MKLocalPointsOfInterestRequest(center: center.coordinate, radius: min(radius, 5000))
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park, .nationalPark, .beach])
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            let c = item.placemark.coordinate
            let d = 0.0006   // ohne Flächenangabe: als ~100 m großen Park annehmen
            let space = GreenSpace(name: item.name, kind: .park,
                                   minLat: c.latitude - d, minLon: c.longitude - d, maxLat: c.latitude + d, maxLon: c.longitude + d)
            return space.isUnsuitable ? nil : space
        }
    }

    // MARK: - Zwischenspeicher

    private static func cacheURL(center: RouteCoordinate, radius: Double) -> URL {
        // "osm2": mit Flüssen (ältere Zwischenspeicher ohne Flüsse werden nicht mehr verwendet)
        let key = String(format: "osm2_%.2f_%.2f_%d.json", center.latitude, center.longitude, Int(radius / 1000))
        return URL.cachesDirectory.appending(path: key)
    }

    private static func loadCache(center: RouteCoordinate, radius: Double) -> Result? {
        let url = cacheURL(center: center, radius: radius)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 14 * 86_400,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Result.self, from: data)
    }

    private static func saveCache(_ result: Result, center: RouteCoordinate, radius: Double) {
        try? JSONEncoder().encode(result).write(to: cacheURL(center: center, radius: radius), options: .atomic)
    }
}

/// Lässt genau einen Aufrufer durch (für das Rennen zwischen Ergebnis und Frist).
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
